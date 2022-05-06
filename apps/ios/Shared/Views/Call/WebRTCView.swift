//
//  WebRTCView.swift
//  SimpleX (iOS)
//
//  Created by Ian Davies on 29/04/2022.
//  Copyright © 2022 SimpleX Chat. All rights reserved.
//

import SwiftUI
import WebKit

class WebRTCCoordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    var webViewReady: Binding<Bool>
    var webViewMsg: Binding<WCallResponse?>
    private var webView: WKWebView?

    internal init(webViewReady: Binding<Bool>, webViewMsg: Binding<WCallResponse?>) {
        self.webViewReady = webViewReady
        self.webViewMsg = webViewMsg
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webView.allowsBackForwardNavigationGestures = false
        self.webView = webView
        webViewReady.wrappedValue = true
    }

    // receive message from WKWebView
    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        logger.debug("WebRTCCoordinator.userContentController")
        if let data = (message.body as? String)?.data(using: .utf8),
           let msg = try? jsonDecoder.decode(WVAPIMessage.self, from: data) {
            webViewMsg.wrappedValue = msg.resp
        } else {
            logger.error("WebRTCCoordinator.userContentController: invalid message \(String(describing: message.body))")
        }
    }

    func sendCommand(command: WCallCommand) {
        if let webView = webView {
            logger.debug("WebRTCCoordinator.sendCommand")
            let apiCmd = encodeJSON(WVAPICall(command: command))
            let js = "processCommand(\(apiCmd))"
            webView.evaluateJavaScript(js)
        }
    }
}

struct WebRTCView: UIViewRepresentable {
    @Binding var coordinator: WebRTCCoordinator?
    @Binding var webViewReady: Bool
    @Binding var webViewMsg: WCallResponse?

    func makeCoordinator() -> WebRTCCoordinator {
        WebRTCCoordinator(webViewReady: $webViewReady, webViewMsg: $webViewMsg)
    }

    func makeUIView(context: Context) -> WKWebView {
        let wkCoordinator = makeCoordinator()
        DispatchQueue.main.async { coordinator = wkCoordinator }

        let wkController = WKUserContentController()

        let cfg = WKWebViewConfiguration()
        cfg.userContentController = wkController
        cfg.mediaTypesRequiringUserActionForPlayback = []
        cfg.allowsInlineMediaPlayback = true

        let source = "sendMessageToNative = (msg) => webkit.messageHandlers.webrtc.postMessage(JSON.stringify(msg))"
        let script = WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: false)
        wkController.addUserScript(script)
        wkController.add(wkCoordinator, name: "webrtc")

        let wkWebView = WKWebView(frame: .zero, configuration: cfg)
        wkWebView.navigationDelegate = wkCoordinator
        guard let path: String = Bundle.main.path(forResource: "call", ofType: "html", inDirectory: "www") else {
            logger.error("WebRTCView.makeUIView call.html not found")
            return wkWebView
        }
        let localHTMLUrl = URL(fileURLWithPath: path, isDirectory: false)
        wkWebView.loadFileURL(localHTMLUrl, allowingReadAccessTo: localHTMLUrl)
        return wkWebView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        logger.debug("WebRTCView.updateUIView")
    }
}

//struct CallViewDebug: View {
//    @State var coordinator: WebRTCCoordinator? = nil
//    @State var commandStr = ""
//    @State private var webViewMsg: WCallResponse? = nil
//    @FocusState private var keyboardVisible: Bool
//
//    var body: some View {
//        VStack(spacing: 30) {
//            WebRTCView(coordinator: $coordinator, webViewMsg: $webViewMsg).frame(maxHeight: 260)
//                .onChange(of: webViewMsg) { _ in
//                    if let resp = webViewMsg {
//                        commandStr = encodeJSON(resp)
//                    }
//                }
//            TextEditor(text: $commandStr)
//                .focused($keyboardVisible)
//                .disableAutocorrection(true)
//                .textInputAutocapitalization(.never)
//                .padding(.horizontal, 5)
//                .padding(.top, 2)
//                .frame(height: 112)
//                .overlay(
//                    RoundedRectangle(cornerRadius: 10)
//                        .strokeBorder(.secondary, lineWidth: 0.3, antialiased: true)
//                )
//            HStack(spacing: 20) {
//                Button("Copy") {
//                    UIPasteboard.general.string = commandStr
//                }
//                Button("Paste") {
//                    commandStr = UIPasteboard.general.string ?? ""
//                }
//                Button("Clear") {
//                    commandStr = ""
//                }
//                Button("Send") {
//                    do {
//                        let command = try jsonDecoder.decode(WCallCommand.self, from: commandStr.data(using: .utf8)!)
//                        if let c = coordinator {
//                            c.sendCommand(command: command)
//                        }
//                    } catch {
//                        print(error)
//                    }
//                }
//            }
//            HStack(spacing: 20) {
//                Button("Capabilities") {
//
//                }
//                Button("Start") {
//                    if let c = coordinator {
//                        c.sendCommand(command: .start(media: .video))
//                    }
//                }
//                Button("Accept") {
//
//                }
//                Button("Answer") {
//
//                }
//                Button("ICE") {
//
//                }
//                Button("End") {
//
//                }
//            }
//        }
//    }
//}
//
//struct CallViewDebug_Previews: PreviewProvider {
//    static var previews: some View {
//        CallViewDebug()
//    }
//}
