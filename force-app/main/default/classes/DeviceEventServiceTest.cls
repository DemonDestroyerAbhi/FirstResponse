@IsTest
private class DeviceEventServiceTest {
    @TestSetup
    static void setup() {
        Account acct = new Account(Name = 'Northwind Clinics');
        insert acct;
        Asset sensor = new Asset(Name = 'Basement leak sensor', AccountId = acct.Id, Device_Id__c = 'dev-1');
        insert sensor;
        insert new Entitlement(Name = 'Gold AMC', AccountId = acct.Id, AssetId = sensor.Id);
    }

    static void useRules() {
        DeviceEventService.mappingsOverride = new List<Event_Mapping__mdt>{
            new Event_Mapping__mdt(
                DeveloperName = 'Flood',
                Active__c = true,
                Create_Work_Order__c = true,
                Event_Type__c = 'flood_detected',
                Priority__c = 'Critical',
                Subject__c = 'Water leak detected at {AssetName}'
            ),
            new Event_Mapping__mdt(
                DeveloperName = 'Motion_Human',
                Active__c = true,
                Create_Work_Order__c = true,
                Event_Type__c = 'motion_detected',
                Sub_Type__c = 'human',
                Priority__c = 'High',
                Outside_Business_Hours_Only__c = true
            )
        };
    }

    static Device_Event__e event(String eventId, String eventType, String subType) {
        return new Device_Event__e(
            Event_Id__c = eventId,
            Device_Id__c = 'dev-1',
            Event_Type__c = eventType,
            Sub_Type__c = subType,
            Occurred_At__c = Datetime.newInstanceGmt(2026, 10, 7, 2, 0, 0),
            Source__c = 'emulator'
        );
    }

    @IsTest
    static void publishedEventOpensEntitledWorkOrder() {
        // Goes through the real trigger and the packaged Flood_Detected mapping record.
        Test.startTest();
        EventBus.publish(event('evt-1', 'flood_detected', null));
        Test.stopTest();

        WorkOrder wo = [
            SELECT Subject, Priority, EntitlementId, AssetId, SlaStartDate, Source_Event_Id__c, Description
            FROM WorkOrder
        ];
        Assert.areEqual('Water leak detected at Basement leak sensor', wo.Subject);
        Assert.areEqual('Critical', wo.Priority);
        Assert.areEqual([SELECT Id FROM Entitlement].Id, wo.EntitlementId);
        Assert.areEqual([SELECT Id FROM Asset].Id, wo.AssetId);
        Assert.areEqual(Datetime.newInstanceGmt(2026, 10, 7, 2, 0, 0), wo.SlaStartDate);
        Assert.areEqual('evt-1', wo.Source_Event_Id__c);
        Assert.isTrue(wo.Description.contains('Entitlement: Gold AMC'));
    }

    @IsTest
    static void sameEventTwiceOpensOneWorkOrder() {
        useRules();

        List<DeviceEventService.Result> first = DeviceEventService.handle(
            new List<Device_Event__e>{ event('evt-1', 'flood_detected', null), event('evt-1', 'flood_detected', null) }
        );
        List<DeviceEventService.Result> again = DeviceEventService.handle(
            new List<Device_Event__e>{ event('evt-1', 'flood_detected', null) }
        );

        Assert.areEqual(1, [SELECT COUNT() FROM WorkOrder]);
        Assert.areEqual(DeviceEventService.Outcome.DUPLICATE_EVENT, first[0].outcome);
        Assert.areEqual(DeviceEventService.Outcome.CREATED, first[1].outcome);
        Assert.areEqual(DeviceEventService.Outcome.DUPLICATE_EVENT, again[0].outcome);
    }

    @IsTest
    static void newEventWhileWorkOrderOpenIsFolded() {
        useRules();
        DeviceEventService.handle(new List<Device_Event__e>{ event('evt-1', 'flood_detected', null) });

        List<DeviceEventService.Result> results = DeviceEventService.handle(
            new List<Device_Event__e>{ event('evt-2', 'flood_detected', null) }
        );

        Assert.areEqual(DeviceEventService.Outcome.OPEN_WORK_ORDER_EXISTS, results[0].outcome);
        Assert.areEqual(1, [SELECT COUNT() FROM WorkOrder]);
    }

    @IsTest
    static void skipsUnmappedUnknownAndBusinessHoursEvents() {
        useRules();
        DeviceEventService.withinBusinessHoursOverride = true;
        Device_Event__e unknownDevice = event('evt-3', 'flood_detected', null);
        unknownDevice.Device_Id__c = 'dev-404';

        List<DeviceEventService.Result> results = DeviceEventService.handle(
            new List<Device_Event__e>{
                event('evt-1', 'button_press', null),
                event('evt-2', 'motion_detected', 'human'),
                unknownDevice,
                event('evt-4', 'motion_detected', 'vehicle')
            }
        );

        Assert.areEqual(DeviceEventService.Outcome.NO_MAPPING, results[0].outcome);
        Assert.areEqual(DeviceEventService.Outcome.INSIDE_BUSINESS_HOURS, results[1].outcome);
        Assert.areEqual(DeviceEventService.Outcome.NO_MAPPING, results[2].outcome);
        Assert.areEqual(DeviceEventService.Outcome.UNKNOWN_DEVICE, results[3].outcome);
        Assert.areEqual(0, [SELECT COUNT() FROM WorkOrder]);
    }

    @IsTest
    static void afterHoursPersonOpensWorkOrder() {
        useRules();
        DeviceEventService.withinBusinessHoursOverride = false;

        List<DeviceEventService.Result> results = DeviceEventService.handle(
            new List<Device_Event__e>{ event('evt-1', 'motion_detected', 'human') }
        );

        Assert.areEqual(DeviceEventService.Outcome.CREATED, results[0].outcome);
        Assert.areEqual('High', [SELECT Priority FROM WorkOrder].Priority);
    }

    @IsTest
    static void workOrderWithoutEntitlementIsFlagged() {
        useRules();
        delete [SELECT Id FROM Entitlement];

        DeviceEventService.handle(new List<Device_Event__e>{ event('evt-1', 'flood_detected', null) });

        WorkOrder wo = [SELECT EntitlementId, Description FROM WorkOrder];
        Assert.isNull(wo.EntitlementId);
        Assert.isTrue(wo.Description.contains('No active entitlement'));
    }
}
