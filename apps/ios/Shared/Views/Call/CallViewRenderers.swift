//
// Created by Avently on 09.02.2023.
// Copyright (c) 2023 SimpleX Chat. All rights reserved.
//

import SwiftUI
import WebRTC
import SimpleXChat
import AVKit

struct CallViewRemote: UIViewRepresentable {
    var client: WebRTCClient
    var activeCall: Binding<WebRTCClient.Call?>
    @State var pipShown: Bool = false
    @State var enablePip: (Bool) -> Void = {_ in }
    @Binding var activeCallViewIsCollapsed: Bool

    init(client: WebRTCClient, activeCall: Binding<WebRTCClient.Call?>, activeCallViewIsCollapsed: Binding<Bool>) {
        self.client = client
        self.activeCall = activeCall
        self._activeCallViewIsCollapsed = activeCallViewIsCollapsed
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        if let call = activeCall.wrappedValue {
            let remoteRenderer = RTCMTLVideoView(frame: view.frame)
            remoteRenderer.videoContentMode = .scaleAspectFill
            client.addRemoteRenderer(call, remoteRenderer)
            addSubviewAndResize(remoteRenderer, into: view)

            if AVPictureInPictureController.isPictureInPictureSupported() {
                makeViewWithRTCRenderer(call, view, context)
            }
        }
        return view
    }
    
    func makeViewWithRTCRenderer(_ call: WebRTCClient.Call, _ view: UIView, _ context: Context) {
        let pipRemoteRenderer = RTCMTLVideoView(frame: view.frame)
        pipRemoteRenderer.videoContentMode = .scaleAspectFill
        
        let pipVideoCallViewController = AVPictureInPictureVideoCallViewController()
        pipVideoCallViewController.preferredContentSize = CGSize(width: 1080, height: 1920)
        addSubviewAndResize(pipRemoteRenderer, into: pipVideoCallViewController.view)
        let pipContentSource = AVPictureInPictureController.ContentSource(
            activeVideoCallSourceView: view,
            contentViewController: pipVideoCallViewController
        )
        
        let pipController = AVPictureInPictureController(contentSource: pipContentSource)
        pipController.canStartPictureInPictureAutomaticallyFromInline = true
        pipController.delegate = context.coordinator
        context.coordinator.willShowHide = { show in
            if show {
                client.addRemoteRenderer(call, pipRemoteRenderer)
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    activeCallViewIsCollapsed = false
                }
            }
        }
        context.coordinator.didShowHide = { show in
            if show {
                activeCallViewIsCollapsed = true
            } else {
                client.removeRemoteRenderer(call, pipRemoteRenderer)
            }
            pipShown = show
        }
        DispatchQueue.main.async {
            enablePip = { enable in
                if enable != pipShown /* pipController.isPictureInPictureActive */ {
                    if enable {
                        pipController.startPictureInPicture()
                    } else {
                        pipController.stopPictureInPicture()
                    }
                    pipShown = enable
                }
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func updateUIView(_ view: UIView, context: Context) {
        logger.debug("CallView.updateUIView remote")
        DispatchQueue.main.async {
            if activeCallViewIsCollapsed != pipShown {
                enablePip(activeCallViewIsCollapsed)
            }
        }
    }
    
    // MARK: - Coordinator
    class Coordinator: NSObject, AVPictureInPictureControllerDelegate {
        var willShowHide: (Bool) -> Void = { _ in }
        var didShowHide: (Bool) -> Void = { _ in }
        
        func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
            willShowHide(true)
        }

        func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
            didShowHide(true)
        }

        func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
            logger.error("PiP failed to start: \(error.localizedDescription)")
        }
        
        func pictureInPictureControllerWillStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
            willShowHide(false)
        }
        
        func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
            didShowHide(false)
        }
    }
    
    class SampleBufferVideoCallView: UIView {
        override class var layerClass: AnyClass {
            get { return AVSampleBufferDisplayLayer.self }
        }
        
        var sampleBufferDisplayLayer: AVSampleBufferDisplayLayer {
            return layer as! AVSampleBufferDisplayLayer
        }
    }
}

struct CallViewLocal: UIViewRepresentable {
    var client: WebRTCClient
    var activeCall: Binding<WebRTCClient.Call?>
    var localRendererAspectRatio: Binding<CGFloat?>

    init(client: WebRTCClient, activeCall: Binding<WebRTCClient.Call?>, localRendererAspectRatio: Binding<CGFloat?>) {
        self.client = client
        self.activeCall = activeCall
        self.localRendererAspectRatio = localRendererAspectRatio
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        if let call = activeCall.wrappedValue {
            let localRenderer = RTCEAGLVideoView(frame: .zero)
            client.addLocalRenderer(call, localRenderer)
            client.startCaptureLocalVideo(call)
            addSubviewAndResize(localRenderer, into: view)
        }
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        logger.debug("CallView.updateUIView local")
    }
}

private func addSubviewAndResize(_ view: UIView, into containerView: UIView) {
    containerView.addSubview(view)
    view.translatesAutoresizingMaskIntoConstraints = false
    containerView.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "H:|[view]|",
        options: [],
        metrics: nil,
        views: ["view": view]))

    containerView.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "V:|[view]|",
        options: [],
        metrics: nil,
        views: ["view": view]))
    containerView.layoutIfNeeded()
}
