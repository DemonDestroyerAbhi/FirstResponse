trigger DeviceEventTrigger on Device_Event__e(after insert) {
    DeviceEventService.handle(Trigger.new);
}
