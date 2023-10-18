"use strict";
// Override defaults to enable worker on Chrome and Safari
useWorker = window.safari !== undefined || navigator.userAgent.indexOf("Chrome") != -1;
// Create WebSocket connection.
const socket = new WebSocket(`ws://${location.host}`);
socket.addEventListener("open", (_event) => {
    console.log("Opened socket");
    sendMessageToNative = (msg) => {
        console.log("Message to server: ", msg);
        socket.send(JSON.stringify(msg));
    };
});
socket.addEventListener("message", (event) => {
    const parsed = JSON.parse(event.data);
    reactOnMessageFromServer(parsed);
    processCommand(parsed);
    console.log("Message from server: ", event.data);
});
socket.addEventListener("close", (_event) => {
    console.log("Closed socket");
    sendMessageToNative = (_msg) => {
        console.log("Tried to send message to native but the socket was closed already");
    };
    window.close();
});
function endCallManually() {
    sendMessageToNative({ resp: { type: "end" } });
}
function toggleAudioManually() {
    if (activeCall === null || activeCall === void 0 ? void 0 : activeCall.localMedia) {
        document.getElementById("toggle-audio").innerHTML = toggleMedia(activeCall.localStream, CallMediaType.Audio)
            ? '<img src="/desktop/images/ic_mic.svg" />'
            : '<img src="/desktop/images/ic_mic_off.svg" />';
    }
}
function toggleSpeakerManually() {
    if (activeCall === null || activeCall === void 0 ? void 0 : activeCall.remoteStream) {
        document.getElementById("toggle-speaker").innerHTML = toggleMedia(activeCall.remoteStream, CallMediaType.Audio)
            ? '<img src="/desktop/images/ic_volume_up.svg" />'
            : '<img src="/desktop/images/ic_volume_down.svg" />';
    }
}
function toggleVideoManually() {
    if (activeCall === null || activeCall === void 0 ? void 0 : activeCall.localMedia) {
        document.getElementById("toggle-video").innerHTML = toggleMedia(activeCall.localStream, CallMediaType.Video)
            ? '<img src="/desktop/images/ic_videocam_filled.svg" />'
            : '<img src="/desktop/images/ic_videocam_off.svg" />';
    }
}
function reactOnMessageFromServer(msg) {
    var _a;
    switch ((_a = msg.command) === null || _a === void 0 ? void 0 : _a.type) {
        case "capabilities":
            document.getElementById("info-block").className = msg.command.media;
            break;
        case "offer":
        case "start":
            document.getElementById("toggle-audio").style.display = "inline-block";
            document.getElementById("toggle-speaker").style.display = "inline-block";
            if (msg.command.media == "video") {
                document.getElementById("toggle-video").style.display = "inline-block";
            }
            document.getElementById("info-block").className = msg.command.media;
            break;
        case "description":
            updateCallInfoView(msg.command.state, msg.command.description);
            if ((activeCall === null || activeCall === void 0 ? void 0 : activeCall.connection.connectionState) == "connected") {
                document.getElementById("progress").style.display = "none";
                if (document.getElementById("info-block").className == CallMediaType.Audio) {
                    document.getElementById("audio-call-icon").style.display = "block";
                }
            }
            break;
    }
}
function updateCallInfoView(state, description) {
    document.getElementById("state").innerText = state;
    document.getElementById("description").innerText = description;
}
//# sourceMappingURL=ui.js.map