@IsTest
private class EvidenceControllerTest {
    private class RelayMock implements HttpCalloutMock {
        Integer status;
        HttpRequest last;

        RelayMock(Integer status) {
            this.status = status;
        }

        public HttpResponse respond(HttpRequest req) {
            last = req;
            HttpResponse res = new HttpResponse();
            res.setStatusCode(status);
            if (req.getEndpoint().endsWith('/snapshot')) {
                res.setHeader('Content-Type', 'image/png');
                res.setBodyAsBlob(Blob.valueOf('png-bytes'));
            } else {
                res.setHeader('Content-Type', 'application/sdp');
                res.setBody('v=0 answer');
            }
            return res;
        }
    }

    static Id workOrderId(String deviceId) {
        WorkOrder wo = new WorkOrder(Subject = 'Leak', Device_Id__c = deviceId);
        insert wo;
        return wo.Id;
    }

    @IsTest
    static void snapshotIsReturnedAsDataUri() {
        Id woId = workOrderId('dev-1');
        RelayMock mock = new RelayMock(200);
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        String uri = EvidenceController.getSnapshot(woId);
        Test.stopTest();

        Assert.areEqual('data:image/png;base64,' + EncodingUtil.base64Encode(Blob.valueOf('png-bytes')), uri);
        Assert.areEqual(EvidenceController.RELAY + '/api/devices/dev-1/snapshot', mock.last.getEndpoint());
    }

    @IsTest
    static void liveViewForwardsTheOffer() {
        Id woId = workOrderId('dev-1');
        RelayMock mock = new RelayMock(200);
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        Assert.areEqual('v=0 answer', EvidenceController.startLiveView(woId, 'v=0 offer'));
        Test.stopTest();

        Assert.areEqual('POST', mock.last.getMethod());
        Assert.areEqual('v=0 offer', mock.last.getBody());
    }

    @IsTest
    static void relayErrorsAndUnlinkedWorkOrdersAreReported() {
        Test.setMock(HttpCalloutMock.class, new RelayMock(502));
        Id linked = workOrderId('dev-1');
        Id unlinked = workOrderId(null);

        Test.startTest();
        for (Id woId : new List<Id>{ linked, unlinked }) {
            try {
                EvidenceController.getSnapshot(woId);
                Assert.fail('Expected an AuraHandledException');
            } catch (AuraHandledException e) {
                Assert.isNotNull(e);
            }
        }
        Test.stopTest();
    }
}
