import { LightningElement, api } from "lwc";
import getSnapshot from "@salesforce/apex/EvidenceController.getSnapshot";
import startLiveView from "@salesforce/apex/EvidenceController.startLiveView";

const ICE_GATHERING_TIMEOUT_MS = 3000;

/**
 * Shows evidence from the device that opened a work order. Ring blocks browser calls by
 * CORS, so both the snapshot and the WHEP signalling go through Apex and the relay; only
 * the media itself flows directly between the browser and Ring over WebRTC.
 */
export default class DeviceEvidence extends LightningElement {
    @api recordId;

    snapshotUrl;
    error;
    busy = false;
    live = false;
    peer;

    get showSnapshot() {
        return !this.live && Boolean(this.snapshotUrl);
    }

    get hideVideo() {
        return !this.live;
    }

    get isEmpty() {
        return !this.live && !this.snapshotUrl && !this.busy && !this.error;
    }

    disconnectedCallback() {
        this.stopLiveView();
    }

    async loadSnapshot() {
        this.stopLiveView();
        await this.run(async () => {
            this.snapshotUrl = await getSnapshot({ workOrderId: this.recordId });
        });
    }

    async startLiveView() {
        await this.run(async () => {
            const peer = new RTCPeerConnection();
            this.peer = peer;
            peer.addTransceiver("video", { direction: "recvonly" });
            peer.addTransceiver("audio", { direction: "recvonly" });
            peer.ontrack = (event) => {
                const video = this.template.querySelector("video");
                if (video && event.streams[0]) video.srcObject = event.streams[0];
            };

            await peer.setLocalDescription(await peer.createOffer());
            // WHEP here is a single request/response, so send the offer with all candidates.
            await waitForIceGathering(peer);

            const answer = await startLiveView({ workOrderId: this.recordId, sdpOffer: peer.localDescription.sdp });
            await peer.setRemoteDescription({ type: "answer", sdp: answer });
            this.live = true;
        });
        if (!this.live) this.stopLiveView();
    }

    stopLiveView() {
        if (this.peer) {
            this.peer.close();
            this.peer = undefined;
        }
        const video = this.template.querySelector("video");
        if (video) video.srcObject = null;
        this.live = false;
    }

    async run(work) {
        this.busy = true;
        this.error = undefined;
        try {
            await work();
        } catch (e) {
            this.error = e?.body?.message ?? e?.message ?? "Something went wrong";
        } finally {
            this.busy = false;
        }
    }
}

function waitForIceGathering(peer) {
    if (peer.iceGatheringState === "complete") return Promise.resolve();
    return new Promise((resolve) => {
        const done = () => {
            peer.removeEventListener("icegatheringstatechange", check);
            clearTimeout(timer);
            resolve();
        };
        const check = () => {
            if (peer.iceGatheringState === "complete") done();
        };
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        const timer = setTimeout(done, ICE_GATHERING_TIMEOUT_MS);
        peer.addEventListener("icegatheringstatechange", check);
    });
}
