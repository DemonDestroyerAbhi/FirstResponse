/**
 * Backs the Device Evidence card on Work Orders. Ring blocks browser calls by CORS, so the
 * card goes through Apex, and Apex goes through the relay via the FirstResponse_Relay
 * Named Credential (which adds the relay's bearer token).
 */
public with sharing class EvidenceController {
    @TestVisible
    private static final String RELAY = 'callout:FirstResponse_Relay';

    public class EvidenceException extends Exception {
    }

    /** Latest device snapshot as a data: URI the card can drop into an img tag. */
    @AuraEnabled
    public static String getSnapshot(Id workOrderId) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(RELAY + '/api/devices/' + deviceIdFor(workOrderId) + '/snapshot');
        req.setMethod('GET');
        req.setTimeout(20000);
        HttpResponse res = send(req);

        String contentType = res.getHeader('Content-Type');
        if (String.isBlank(contentType) || !contentType.startsWith('image/')) {
            contentType = 'image/jpeg';
        }
        return 'data:' + contentType + ';base64,' + EncodingUtil.base64Encode(res.getBodyAsBlob());
    }

    /** Exchanges the browser's WebRTC SDP offer for Ring's WHEP answer. */
    @AuraEnabled
    public static String startLiveView(Id workOrderId, String sdpOffer) {
        if (String.isBlank(sdpOffer)) {
            throw new AuraHandledException('Missing SDP offer');
        }
        HttpRequest req = new HttpRequest();
        req.setEndpoint(RELAY + '/api/devices/' + deviceIdFor(workOrderId) + '/whep');
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/sdp');
        req.setBody(sdpOffer);
        req.setTimeout(20000);
        return send(req).getBody();
    }

    private static String deviceIdFor(Id workOrderId) {
        List<WorkOrder> rows = [
            SELECT Device_Id__c
            FROM WorkOrder
            WHERE Id = :workOrderId
            WITH USER_MODE
            LIMIT 1
        ];
        if (rows.isEmpty() || String.isBlank(rows[0].Device_Id__c)) {
            throw new AuraHandledException('This work order is not linked to a device.');
        }
        return EncodingUtil.urlEncode(rows[0].Device_Id__c, 'UTF-8');
    }

    private static HttpResponse send(HttpRequest req) {
        HttpResponse res;
        try {
            res = new Http().send(req);
        } catch (CalloutException e) {
            throw new AuraHandledException('Could not reach the FirstResponse relay: ' + e.getMessage());
        }
        if (res.getStatusCode() >= 300) {
            throw new AuraHandledException('Relay returned ' + res.getStatusCode() + ': ' + res.getBody().left(200));
        }
        return res;
    }
}
