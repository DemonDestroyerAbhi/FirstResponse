@IsTest
private class EntitlementResolverTest {
    @TestSetup
    static void setup() {
        Account acct = new Account(Name = 'Northwind Clinics');
        insert acct;
        insert new List<Asset>{
            new Asset(Name = 'Basement leak sensor', AccountId = acct.Id, Device_Id__c = 'dev-asset'),
            new Asset(Name = 'Lobby camera', AccountId = acct.Id, Device_Id__c = 'dev-contract'),
            new Asset(Name = 'Back door sensor', AccountId = acct.Id, Device_Id__c = 'dev-account')
        };
    }

    static Map<String, Asset> assets() {
        Map<String, Asset> byDevice = new Map<String, Asset>();
        for (Asset a : [SELECT Id, AccountId, Device_Id__c FROM Asset]) {
            byDevice.put(a.Device_Id__c, a);
        }
        return byDevice;
    }

    @IsTest
    static void prefersAssetThenContractThenAccount() {
        Map<String, Asset> byDevice = assets();
        Id accountId = byDevice.get('dev-asset').AccountId;

        Pricebook2 pb = new Pricebook2(Id = Test.getStandardPricebookId(), IsActive = true);
        update pb;
        Product2 product = new Product2(Name = 'Annual maintenance', IsActive = true);
        insert product;
        PricebookEntry pbe = new PricebookEntry(
            Pricebook2Id = pb.Id,
            Product2Id = product.Id,
            UnitPrice = 100,
            IsActive = true
        );
        insert pbe;
        ServiceContract contract = new ServiceContract(Name = 'AMC 2026', AccountId = accountId, Pricebook2Id = pb.Id);
        insert contract;
        insert new ContractLineItem(
            ServiceContractId = contract.Id,
            AssetId = byDevice.get('dev-contract').Id,
            PricebookEntryId = pbe.Id,
            Quantity = 1,
            UnitPrice = 100
        );

        Entitlement onAsset = new Entitlement(
            Name = 'Asset SLA',
            AccountId = accountId,
            AssetId = byDevice.get('dev-asset').Id
        );
        Entitlement onContract = new Entitlement(
            Name = 'Contract SLA',
            AccountId = accountId,
            ServiceContractId = contract.Id
        );
        Entitlement onAccount = new Entitlement(Name = 'Account SLA', AccountId = accountId);
        insert new List<Entitlement>{ onAsset, onContract, onAccount };

        Map<String, EntitlementResolver.Resolution> result = EntitlementResolver.resolve(
            new Set<String>{ 'dev-asset', 'dev-contract', 'dev-account', 'dev-unknown' },
            Date.today()
        );

        Assert.areEqual(onAsset.Id, result.get('dev-asset').entitlement.Id);
        Assert.areEqual(onContract.Id, result.get('dev-contract').entitlement.Id);
        Assert.areEqual(onAccount.Id, result.get('dev-account').entitlement.Id);
        Assert.isFalse(result.get('dev-unknown').hasAsset());
        Assert.isFalse(result.get('dev-unknown').hasEntitlement());
    }

    @IsTest
    static void ignoresExpiredEntitlements() {
        Asset a = assets().get('dev-asset');
        insert new Entitlement(
            Name = 'Expired SLA',
            AccountId = a.AccountId,
            AssetId = a.Id,
            StartDate = Date.today().addYears(-2),
            EndDate = Date.today().addYears(-1)
        );

        EntitlementResolver.Resolution r = EntitlementResolver.resolve(new Set<String>{ 'dev-asset' }, Date.today())
            .get('dev-asset');

        Assert.isTrue(r.hasAsset());
        Assert.isFalse(r.hasEntitlement());
    }
}
