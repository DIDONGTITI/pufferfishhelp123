;(async function run() {
  const START_E2EE_CALL_BTN = "start-e2ee-call"
  const START_CALL_BTN = "start-call"
  const URL_FOR_PEER = "url-for-peer"
  const COPY_URL_FOR_PEER_BTN = "copy-url-for-peer"
  const DATA_FOR_PEER = "data-for-peer"
  const COPY_DATA_FOR_PEER_BTN = "copy-data-for-peer"
  const PASS_DATA_TO_PEER_TEXT = "pass-data-to-peer"
  const CHAT_COMMAND_FOR_PEER = "chat-command-for-peer"
  const COMMAND_TO_PROCESS = "command-to-process"
  const PROCESS_COMMAND_BTN = "process-command"
  const urlForPeer = document.getElementById(URL_FOR_PEER)
  const dataForPeer = document.getElementById(DATA_FOR_PEER)
  const passDataToPeerText = document.getElementById(PASS_DATA_TO_PEER_TEXT)
  const chatCommandForPeer = document.getElementById(CHAT_COMMAND_FOR_PEER)
  const commandToProcess = document.getElementById(COMMAND_TO_PROCESS)
  const processCommandButton = document.getElementById(PROCESS_COMMAND_BTN)
  const startE2EECallButton = document.getElementById(START_E2EE_CALL_BTN)
  const {resp} = await processCommand({command: {type: "capabilities", useWorker: true}})
  if (resp?.capabilities?.encryption) {
    startE2EECallButton.onclick = startCall(true)
  } else {
    startE2EECallButton.style.display = "none"
  }
  const startCallButton = document.getElementById(START_CALL_BTN)
  startCallButton.onclick = startCall()
  const copyUrlButton = document.getElementById(COPY_URL_FOR_PEER_BTN)
  copyUrlButton.onclick = () => {
    navigator.clipboard.writeText(urlForPeer.innerText)
    commandToProcess.style.display = ""
    processCommandButton.style.display = ""
  }
  const copyDataButton = document.getElementById(COPY_DATA_FOR_PEER_BTN)
  copyDataButton.onclick = () => {
    navigator.clipboard.writeText(dataForPeer.innerText)
    commandToProcess.style.display = ""
    processCommandButton.style.display = ""
  }
  processCommandButton.onclick = () => {
    sendCommand(JSON.parse(commandToProcess.value))
    commandToProcess.value = ""
  }
  const parsed = new URLSearchParams(document.location.hash.substring(1))
  let apiCallStr = parsed.get("command")
  if (apiCallStr) {
    startE2EECallButton.style.display = "none"
    startCallButton.style.display = "none"
    await sendCommand(JSON.parse(decodeURIComponent(apiCallStr)))
  }

  function startCall(encryption) {
    return async () => {
      let aesKey
      if (encryption) {
        const key = await crypto.subtle.generateKey({name: "AES-GCM", length: 256}, true, ["encrypt", "decrypt"])
        const keyBytes = await crypto.subtle.exportKey("raw", key)
        aesKey = callCrypto.decodeAscii(callCrypto.encodeBase64(new Uint8Array(keyBytes)))
      }
      sendCommand({command: {type: "start", media: "video", aesKey, useWorker: true}})
      startE2EECallButton.style.display = "none"
      startCallButton.style.display = "none"
    }
  }

  async function sendCommand(apiCall) {
    try {
      console.log(apiCall)
      const {command} = apiCall
      const {resp} = await processCommand(apiCall)
      console.log(resp)
      switch (resp.type) {
        case "offer": {
          const {media, aesKey} = command
          const {offer, iceCandidates, capabilities} = resp
          const peerWCommand = {
            command: {type: "offer", offer, iceCandidates, media, aesKey: capabilities.encryption ? aesKey : undefined, useWorker: true},
          }
          const url = new URL(document.location)
          parsed.set("command", encodeURIComponent(JSON.stringify(peerWCommand)))
          url.hash = parsed.toString()
          urlForPeer.innerText = url.toString()
          dataForPeer.innerText = JSON.stringify(peerWCommand)
          copyUrlButton.style.display = ""
          copyDataButton.style.display = ""

          // const webRTCCallOffer = {callType: {media, capabilities}, rtcSession: {rtcSession: offer, rtcIceCandidates: iceCandidates}}
          // const peerChatCommand = `/_call @${parsed.contact} offer ${JSON.stringify(webRTCCallOffer)}`
          // chatCommandForPeer.innerText = peerChatCommand
          return
        }
        case "answer": {
          const {answer, iceCandidates} = resp
          const peerWCommand = {command: {type: "answer", answer, iceCandidates}}
          dataForPeer.innerText = JSON.stringify(peerWCommand)
          copyUrlButton.style.display = "none"
          copyDataButton.style.display = ""

          // const webRTCSession = {rtcSession: answer, rtcIceCandidates: iceCandidates}
          // const peerChatCommand = `/_call @${parsed.contact} answer ${JSON.stringify(webRTCSession)}`
          // chatCommandForPeer.innerText = peerChatCommand
          return
        }
        case "ok":
          if ((command.type = "answer")) {
            console.log("connecting")
            commandToProcess.style.display = "none"
            processCommandButton.style.display = "none"
          }
          return
      }
    } catch (e) {
      console.log("error: ", e)
    }
  }
})()
