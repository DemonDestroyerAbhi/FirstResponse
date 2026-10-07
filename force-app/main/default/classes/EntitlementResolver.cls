/**
 * Resolves Ring device ids to the Asset they're installed on and the Entitlement that
 * governs service for that asset on a given date.
 *
 * Lookup order for the entitlement, most specific first:
 *   1. An entitlement on the asset itself
 *   2. An entitlement on a service contract that covers the asset (contract line item)
 *   3. An account-level entitlement (no asset, no service contract)
 */
public inherited sharing class EntitlementResolver {
    public class Resolution {
        public Asset asset;
        public Entitlement entitlement;

        public Boolean hasAsset() {
            return asset != null;
        }

        public Boolean hasEntitlement() {
            return entitlement != null;
        }
    }

    /**
     * @param deviceIds Ring device ids
     * @param onDate    the date the entitlement must be active on (the event date)
     * @return one Resolution per device id; devices with no matching Asset map to an empty Resolution
     */
    public static Map<String, Resolution> resolve(Set<String> deviceIds, Date onDate) {
        Map<String, Resolution> result = new Map<String, Resolution>();
        for (String deviceId : deviceIds) {
            result.put(deviceId, new Resolution());
        }

        Map<Id, Asset> assetsById = new Map<Id, Asset>();
        Set<Id> accountIds = new Set<Id>();
        for (Asset a : [
            SELECT Id, Name, AccountId, Device_Id__c
            FROM Asset
            WHERE Device_Id__c IN :deviceIds
        ]) {
            result.get(a.Device_Id__c).asset = a;
            assetsById.put(a.Id, a);
            if (a.AccountId != null) {
                accountIds.add(a.AccountId);
            }
        }
        if (assetsById.isEmpty()) {
            return result;
        }

        // Service contracts covering each asset, via contract line items.
        Map<Id, Set<Id>> contractIdsByAsset = new Map<Id, Set<Id>>();
        Set<Id> contractIds = new Set<Id>();
        for (ContractLineItem cli : [
            SELECT AssetId, ServiceContractId
            FROM ContractLineItem
            WHERE AssetId IN :assetsById.keySet()
        ]) {
            if (!contractIdsByAsset.containsKey(cli.AssetId)) {
                contractIdsByAsset.put(cli.AssetId, new Set<Id>());
            }
            contractIdsByAsset.get(cli.AssetId).add(cli.ServiceContractId);
            contractIds.add(cli.ServiceContractId);
        }

        Set<Id> assetIds = assetsById.keySet();
        List<Entitlement> candidates = [
            SELECT Id, Name, AccountId, AssetId, ServiceContractId, SlaProcessId, StartDate, EndDate
            FROM Entitlement
            WHERE
                (AssetId IN :assetIds
                OR ServiceContractId IN :contractIds
                OR (AccountId IN :accountIds
                AND AssetId = NULL
                AND ServiceContractId = NULL))
                AND (StartDate = NULL
                OR StartDate <= :onDate)
                AND (EndDate = NULL
                OR EndDate >= :onDate)
            ORDER BY StartDate DESC NULLS LAST, CreatedDate DESC
        ];

        for (Resolution r : result.values()) {
            if (r.asset != null) {
                r.entitlement = pick(r.asset, contractIdsByAsset.get(r.asset.Id), candidates);
            }
        }
        return result;
    }

    private static Entitlement pick(Asset a, Set<Id> contractIds, List<Entitlement> candidates) {
        Entitlement byContract;
        Entitlement byAccount;
        for (Entitlement e : candidates) {
            if (e.AssetId == a.Id) {
                return e;
            }
            if (
                byContract == null &&
                e.AssetId == null &&
                contractIds != null &&
                contractIds.contains(e.ServiceContractId)
            ) {
                byContract = e;
            }
            if (byAccount == null && e.AssetId == null && e.ServiceContractId == null && e.AccountId == a.AccountId) {
                byAccount = e;
            }
        }
        return byContract != null ? byContract : byAccount;
    }
}
