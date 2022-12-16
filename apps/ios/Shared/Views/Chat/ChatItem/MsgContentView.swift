//
//  MsgContentView.swift
//  SimpleX
//
//  Created by Evgeny on 13/03/2022.
//  Copyright © 2022 SimpleX Chat. All rights reserved.
//

import SwiftUI
import SimpleXChat

private let uiLinkColor = UIColor(red: 0, green: 0.533, blue: 1, alpha: 1)

private let typingIndicators: [Text] = [
    Text("   "),
    (typing() + typing() + typing()),
    (typing(.black) + typing() + typing()),
    (typing(.bold) + typing(.black) + typing()),
    (typing() + typing(.bold) + typing(.black)),
    (typing() + typing() + typing(.bold))
]

private func typing(_ w: Font.Weight = .light) -> Text {
    Text(".").fontWeight(w)
}

struct MsgContentView: View {
    var text: String
    var formattedText: [FormattedText]? = nil
    var sender: String? = nil
    var meta: CIMeta? = nil
    var rightToLeft = false
    @State private var typingIdx = 0
    @State private var timer: Timer?

    var body: some View {
        if meta?.itemLive == true {
            msgContentView()
            .onAppear(perform: showTyping)
            .onChange(of: meta) { _ in showTyping() }
            .onDisappear { timer?.invalidate() }
        } else {
            msgContentView()
        }
    }

    private func showTyping() {
        if meta?.recent == true {
            if typingIdx == 0 { typingIdx = 1 }
            timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { _ in
                if meta?.recent == true {
                    typingIdx += 1
                    if typingIdx == typingIndicators.count { typingIdx = 1 }
                } else {
                    stopTyping()
                }
            }
        } else {
            stopTyping()
        }
    }

    private func stopTyping() {
        timer?.invalidate()
        typingIdx = 0
        timer = nil
    }

    private func msgContentView() -> Text {
        var v = messageText(text, formattedText, sender)
        if let meta = meta {
            if meta.itemLive {
                v = v + typingIndicator()
            }
            v = v + reserveSpaceForMeta(meta.timestampText, meta.itemEdited)
        }
        return v
    }

    private func typingIndicator() -> Text {
        typingIndicators[typingIdx]
            .font(.body.monospaced())
            .kerning(-2)
            .foregroundColor(.secondary)
    }

    private func reserveSpaceForMeta(_ mt: Text, _ edited: Bool) -> Text {
        let reserve = rightToLeft ? "\n" : edited ? "          " : "      "
        return (Text(reserve) + mt)
            .font(.caption)
            .foregroundColor(.clear)
    }
}

func messageText(_ text: String, _ formattedText: [FormattedText]?, _ sender: String?, preview: Bool = false) -> Text {
    let s = text
    var res: Text
    if let ft = formattedText, ft.count > 0 {
        res = formatText(ft[0], preview)
        var i = 1
        while i < ft.count {
            res = res + formatText(ft[i], preview)
            i = i + 1
        }
    } else {
        res = Text(s)
    }

    if let s = sender {
        let t = Text(s)
        return (preview ? t : t.fontWeight(.medium)) + Text(": ") + res
    } else {
        return res
    }
}

private func formatText(_ ft: FormattedText, _ preview: Bool) -> Text {
    let t = ft.text
    if let f = ft.format {
        switch (f) {
        case .bold: return Text(t).bold()
        case .italic: return Text(t).italic()
        case .strikeThrough: return Text(t).strikethrough()
        case .snippet: return Text(t).font(.body.monospaced())
        case .secret: return Text(t).foregroundColor(.clear).underline(color: .primary)
        case let .colored(color): return Text(t).foregroundColor(color.uiColor)
        case .uri: return linkText(t, t, preview, prefix: "")
        case let .simplexLink(linkType, simplexUri, trustedUri, smpHosts):
            switch privacySimplexLinkModeDefault.get() {
            case .description: return linkText(simplexLinkText(linkType, smpHosts), simplexUri, preview, prefix: "")
            case .full: return linkText(t, simplexUri, preview, prefix: "")
            case .browser: return trustedUri
                                    ? linkText(t, t, preview, prefix: "")
                                    : linkText(t, t, preview, prefix: "", color: .red, uiColor: .red)
            }
        case .email: return linkText(t, t, preview, prefix: "mailto:")
        case .phone: return linkText(t, t.replacingOccurrences(of: " ", with: ""), preview, prefix: "tel:")
        }
    } else {
        return Text(t)
    }
}

private func linkText(_ s: String, _ link: String, _ preview: Bool, prefix: String, color: Color = Color(uiColor: uiLinkColor), uiColor: UIColor = uiLinkColor) -> Text {
    preview
    ? Text(s).foregroundColor(color).underline(color: color)
    : Text(AttributedString(s, attributes: AttributeContainer([
        .link: NSURL(string: prefix + link) as Any,
        .foregroundColor: uiColor as Any
    ]))).underline()
}

private func simplexLinkText(_ linkType: SimplexLinkType, _ smpHosts: [String]) -> String {
    linkType.description + " " + "(via \(smpHosts.first ?? "?"))"
}

struct MsgContentView_Previews: PreviewProvider {
    static var previews: some View {
        let chatItem = ChatItem.getSample(1, .directSnd, .now, "hello")
        return MsgContentView(
            text: chatItem.text,
            formattedText: chatItem.formattedText,
            sender: chatItem.memberDisplayName,
            meta: chatItem.meta
        )
    }
}
