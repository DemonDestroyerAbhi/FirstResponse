// Seeds the demo: one customer, one sensor asset, a service contract and an entitlement
// that uses the "FirstResponse Work Order SLA" entitlement process (create it first, see
// docs/setup.md). Set DEVICE_ID to the device id from the Ring Playground device list,
// or to the id you pass to the emulator.
//
//   sf apex run --file scripts/apex/seed-demo.apex
String DEVICE_ID = 'playground-doorbell-1';
String PROCESS_NAME = 'FirstResponse Work Order SLA';

Account acct = new Account(Name = 'Northwind Clinics');
insert acct;

Asset sensor = new Asset(Name = 'Clinic 4 - Basement leak sensor', AccountId = acct.Id, Device_Id__c = DEVICE_ID);
insert sensor;

ServiceContract contract = new ServiceContract(
    Name = 'Northwind AMC 2026',
    AccountId = acct.Id,
    StartDate = Date.today().addMonths(-1),
    EndDate = Date.today().addMonths(11)
);
insert contract;

List<SlaProcess> processes = [SELECT Id FROM SlaProcess WHERE Name = :PROCESS_NAME AND IsActive = TRUE LIMIT 1];
if (processes.isEmpty()) {
    System.debug(LoggingLevel.WARN, 'No active entitlement process named "' + PROCESS_NAME + '": milestones will not start.');
}

insert new Entitlement(
    Name = 'Gold AMC - 4h response',
    AccountId = acct.Id,
    AssetId = sensor.Id,
    ServiceContractId = contract.Id,
    StartDate = contract.StartDate,
    EndDate = contract.EndDate,
    SlaProcessId = processes.isEmpty() ? null : processes[0].Id
);
System.debug('Seeded asset ' + sensor.Id + ' for device ' + DEVICE_ID);
