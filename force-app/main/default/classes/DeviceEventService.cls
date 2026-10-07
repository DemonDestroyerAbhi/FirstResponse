/**
 * Turns Device_Event__e platform events into entitlement-checked Work Orders.
 *
 * For each event:
 *   1. Find the active Event_Mapping__mdt rule for its type (and sub type). No rule, no work order.
 *   2. Skip it if a work order already exists for the same event id (idempotency), or an open
 *      work order already exists for the same asset and event type (one leak, one work order).
 *   3. Resolve Asset -> Service Contract -> Entitlement and create the Work Order with the
 *      entitlement attached, so the entitlement process starts its milestones. The SLA clock
 *      starts at the time the device reported the event, not when the record was inserted.
 *
 * Runs from the platform event trigger as the Automated Process user (or the user set in
 * PlatformEventSubscriberConfig), so it deliberately ignores sharing.
 */
public without sharing class DeviceEventService {
    public enum Outcome {
        CREATED,
        DUPLICATE_EVENT,
        OPEN_WORK_ORDER_EXISTS,
        NO_MAPPING,
        INSIDE_BUSINESS_HOURS,
        UNKNOWN_DEVICE
    }

    public class Result {
        public String eventId;
        public Outcome outcome;
        public Id workOrderId;

        Result(String eventId, Outcome outcome) {
            this.eventId = eventId;
            this.outcome = outcome;
        }
    }

    @TestVisible
    private static List<Event_Mapping__mdt> mappingsOverride;
    @TestVisible
    private static Boolean withinBusinessHoursOverride;
    private static Id defaultBusinessHoursId;

    public static List<Result> handle(List<Device_Event__e> events) {
        List<Result> results = new List<Result>();
        Map<String, Event_Mapping__mdt> mappings = loadMappings();

        // Pick a rule for each event; drop the ones no rule wants.
        List<Device_Event__e> candidates = new List<Device_Event__e>();
        Map<String, Event_Mapping__mdt> ruleByEventId = new Map<String, Event_Mapping__mdt>();
        Set<String> seenInBatch = new Set<String>();
        for (Device_Event__e e : events) {
            if (String.isBlank(e.Event_Id__c) || seenInBatch.contains(e.Event_Id__c)) {
                results.add(new Result(e.Event_Id__c, Outcome.DUPLICATE_EVENT));
                continue;
            }
            seenInBatch.add(e.Event_Id__c);

            Event_Mapping__mdt rule = findRule(mappings, e.Event_Type__c, e.Sub_Type__c);
            if (rule == null || !rule.Create_Work_Order__c) {
                results.add(new Result(e.Event_Id__c, Outcome.NO_MAPPING));
            } else if (rule.Outside_Business_Hours_Only__c && isWithinBusinessHours(occurredAt(e))) {
                results.add(new Result(e.Event_Id__c, Outcome.INSIDE_BUSINESS_HOURS));
            } else {
                candidates.add(e);
                ruleByEventId.put(e.Event_Id__c, rule);
            }
        }
        if (candidates.isEmpty()) {
            return results;
        }

        Set<String> eventIds = new Set<String>();
        Set<String> deviceIds = new Set<String>();
        for (Device_Event__e e : candidates) {
            eventIds.add(e.Event_Id__c);
            deviceIds.add(e.Device_Id__c);
        }

        Set<String> existingEventIds = new Set<String>();
        for (WorkOrder wo : [SELECT Source_Event_Id__c FROM WorkOrder WHERE Source_Event_Id__c IN :eventIds]) {
            existingEventIds.add(wo.Source_Event_Id__c);
        }

        Set<String> openKeys = new Set<String>();
        for (WorkOrder wo : [
            SELECT Device_Id__c, Device_Event_Type__c
            FROM WorkOrder
            WHERE Device_Id__c IN :deviceIds AND IsClosed = FALSE
        ]) {
            openKeys.add(openKey(wo.Device_Id__c, wo.Device_Event_Type__c));
        }

        Map<String, EntitlementResolver.Resolution> resolutions = EntitlementResolver.resolve(deviceIds, Date.today());

        List<WorkOrder> toInsert = new List<WorkOrder>();
        List<Device_Event__e> inserted = new List<Device_Event__e>();
        for (Device_Event__e e : candidates) {
            String key = openKey(e.Device_Id__c, e.Event_Type__c);
            EntitlementResolver.Resolution res = resolutions.get(e.Device_Id__c);

            if (existingEventIds.contains(e.Event_Id__c)) {
                results.add(new Result(e.Event_Id__c, Outcome.DUPLICATE_EVENT));
            } else if (openKeys.contains(key)) {
                results.add(new Result(e.Event_Id__c, Outcome.OPEN_WORK_ORDER_EXISTS));
            } else if (res == null || !res.hasAsset()) {
                results.add(new Result(e.Event_Id__c, Outcome.UNKNOWN_DEVICE));
            } else {
                toInsert.add(buildWorkOrder(e, ruleByEventId.get(e.Event_Id__c), res));
                inserted.add(e);
                openKeys.add(key);
            }
        }

        // allOrNone=false: a unique-key clash from a concurrent delivery of the same event
        // must not roll back the rest of the batch.
        Database.SaveResult[] saves = Database.insert(toInsert, false);
        for (Integer i = 0; i < saves.size(); i++) {
            Device_Event__e e = inserted[i];
            if (saves[i].isSuccess()) {
                Result r = new Result(e.Event_Id__c, Outcome.CREATED);
                r.workOrderId = saves[i].getId();
                results.add(r);
            } else if (isDuplicateValue(saves[i])) {
                results.add(new Result(e.Event_Id__c, Outcome.DUPLICATE_EVENT));
            } else {
                // Surfaced in the platform event subscriber's error log; the event isn't retried.
                System.debug(
                    LoggingLevel.ERROR,
                    'Work order insert failed for event ' + e.Event_Id__c + ': ' + saves[i].getErrors()
                );
            }
        }
        return results;
    }

    private static WorkOrder buildWorkOrder(
        Device_Event__e e,
        Event_Mapping__mdt rule,
        EntitlementResolver.Resolution res
    ) {
        Datetime occurred = occurredAt(e);
        WorkOrder wo = new WorkOrder(
            AssetId = res.asset.Id,
            AccountId = res.asset.AccountId,
            Subject = renderSubject(rule.Subject__c, e, res.asset).left(255),
            Priority = String.isBlank(rule.Priority__c) ? 'Medium' : rule.Priority__c,
            Source_Event_Id__c = e.Event_Id__c,
            Device_Id__c = e.Device_Id__c,
            Device_Event_Type__c = e.Event_Type__c,
            Event_Occurred_At__c = occurred,
            Description = describe(e, occurred, res)
        );
        if (res.hasEntitlement()) {
            wo.EntitlementId = res.entitlement.Id;
            wo.ServiceContractId = res.entitlement.ServiceContractId;
            wo.SlaStartDate = occurred;
        }
        return wo;
    }

    private static String describe(Device_Event__e e, Datetime occurred, EntitlementResolver.Resolution res) {
        List<String> lines = new List<String>{
            'Event: ' +
            e.Event_Type__c +
            (String.isBlank(e.Sub_Type__c) ? '' : ' (' + e.Sub_Type__c + ')'),
            'Device: ' +
            e.Device_Id__c +
            (String.isBlank(e.Component_Id__c) ? '' : ', component ' + e.Component_Id__c),
            'Reported at: ' +
            occurred.formatGmt('yyyy-MM-dd HH:mm:ss') +
            ' UTC',
            'Source: ' + (String.isBlank(e.Source__c) ? 'unknown' : e.Source__c)
        };
        if (res.hasEntitlement()) {
            lines.add('Entitlement: ' + res.entitlement.Name);
        } else {
            lines.add('No active entitlement covers this asset. Check the service contract before dispatching.');
        }
        return String.join(lines, '\n');
    }

    @TestVisible
    private static String renderSubject(String template, Device_Event__e e, Asset a) {
        String subject = String.isBlank(template) ? '{EventType} at {AssetName}' : template;
        return subject
            .replace('{EventType}', String.isBlank(e.Event_Type__c) ? '' : e.Event_Type__c)
            .replace('{SubType}', String.isBlank(e.Sub_Type__c) ? '' : e.Sub_Type__c)
            .replace('{AssetName}', a.Name)
            .replace('{DeviceId}', e.Device_Id__c);
    }

    /** Prefers a rule that names the event's sub type over a rule for the whole event type. */
    @TestVisible
    private static Event_Mapping__mdt findRule(
        Map<String, Event_Mapping__mdt> mappings,
        String eventType,
        String subType
    ) {
        if (String.isNotBlank(subType) && mappings.containsKey(ruleKey(eventType, subType))) {
            return mappings.get(ruleKey(eventType, subType));
        }
        return mappings.get(ruleKey(eventType, null));
    }

    private static Map<String, Event_Mapping__mdt> loadMappings() {
        List<Event_Mapping__mdt> rules = mappingsOverride != null
            ? mappingsOverride
            : Event_Mapping__mdt.getAll().values();
        Map<String, Event_Mapping__mdt> byKey = new Map<String, Event_Mapping__mdt>();
        for (Event_Mapping__mdt rule : rules) {
            if (rule.Active__c) {
                byKey.put(ruleKey(rule.Event_Type__c, rule.Sub_Type__c), rule);
            }
        }
        return byKey;
    }

    private static String ruleKey(String eventType, String subType) {
        return (eventType == null ? '' : eventType.toLowerCase()) +
            '|' +
            (subType == null ? '' : subType.toLowerCase());
    }

    private static String openKey(String deviceId, String eventType) {
        return deviceId + '|' + eventType;
    }

    private static Datetime occurredAt(Device_Event__e e) {
        return e.Occurred_At__c != null ? e.Occurred_At__c : Datetime.now();
    }

    private static Boolean isWithinBusinessHours(Datetime t) {
        if (withinBusinessHoursOverride != null) {
            return withinBusinessHoursOverride;
        }
        if (defaultBusinessHoursId == null) {
            List<BusinessHours> defaults = [SELECT Id FROM BusinessHours WHERE IsDefault = TRUE LIMIT 1];
            if (defaults.isEmpty()) {
                return false;
            }
            defaultBusinessHoursId = defaults[0].Id;
        }
        return BusinessHours.isWithin(defaultBusinessHoursId, t);
    }

    private static Boolean isDuplicateValue(Database.SaveResult save) {
        for (Database.Error err : save.getErrors()) {
            if (err.getStatusCode() == StatusCode.DUPLICATE_VALUE) {
                return true;
            }
        }
        return false;
    }
}
