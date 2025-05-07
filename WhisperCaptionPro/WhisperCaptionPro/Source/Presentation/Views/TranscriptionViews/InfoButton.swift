//
//  InfoButton.swift
//  WhisperCaptionPro
//
//  Created by 조형구 on 3/21/25.
//

import SwiftUI

struct InfoButton: View {
    var infoText: String
    @State private var showInfo = false

    init(_ infoText: String) {
        self.infoText = infoText
    }

    var body: some View {
        Button(action: {
            showInfo = true
        }) {
            Image(systemName: "info.circle")
                .foregroundColor(.blue)
        }
        .popover(isPresented: $showInfo) {
            Text(infoText)
                .padding()
        }
        .buttonStyle(BorderlessButtonStyle())
    }
}

#Preview {
    InfoButton("This is an example of info text.")
}
