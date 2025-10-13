//
//  InfoButton.swift
//  CaptionMate
//
//  Created by 조형구 on 3/21/25.
//

import SwiftUI

struct InfoButton: View {
    @Environment(\.locale) private var locale

    @State private var showInfo = false

    var infoText: LocalizedStringKey

    init(_ infoText: LocalizedStringKey) {
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
                .environment(\.locale, locale)
        }
        .onChange(of: locale) { oldValue, newValue in
            if showInfo {
                showInfo = false
            }
        }
        .buttonStyle(BorderlessButtonStyle())
    }
}

#Preview {
    InfoButton("This is an example of info text.")
}
