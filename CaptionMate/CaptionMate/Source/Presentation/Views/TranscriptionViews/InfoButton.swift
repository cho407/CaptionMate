//
//  Copyright 2025 Harrison Cho
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//       http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

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
