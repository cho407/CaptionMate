//
//  LegalView.swift
//  CaptionMate
//
//  Created by 조형구 on 10/8/25.
//

import SwiftUI

struct LegalView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("legal_information")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .imageScale(.large)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            // Tab Selection
            TabView(selection: $selectedTab) {
                PrivacyPolicyView()
                    .tabItem {
                        Label("privacy_policy", systemImage: "hand.raised.fill")
                    }
                    .tag(0)

                ThirdPartyNoticesView()
                    .tabItem {
                        Label("third_party_notices", systemImage: "doc.text.fill")
                    }
                    .tag(1)

                SecurityPolicyView()
                    .tabItem {
                        Label("security_policy", systemImage: "lock.shield.fill")
                    }
                    .tag(2)

                LicenseView()
                    .tabItem {
                        Label("license", systemImage: "doc.plaintext.fill")
                    }
                    .tag(3)
            }
        }
        .frame(width: 700, height: 600)
    }
}

// MARK: - Privacy Policy

struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Privacy Policy")
                    .font(.title.bold())
                    .padding(.bottom, 8)

                Text("Last Updated: January 2025")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 16)

                Group {
                    SectionTitle("Data Collection")
                    Text(
                        "CaptionMate does not collect, store, or transmit any personal data. All processing is done locally on your device."
                    )

                    SectionTitle("File Access")
                    Text(
                        "The app only accesses audio/video files that you explicitly select through the file picker. We do not access any files without your direct action."
                    )

                    SectionTitle("Network Usage")
                    Text(
                        "Network connectivity is used solely for downloading AI models from Hugging Face. No user data or usage analytics are transmitted."
                    )

                    SectionTitle("Local Storage")
                    Text(
                        "App preferences and settings are stored locally using UserDefaults. AI models are downloaded and cached locally on your device."
                    )

                    SectionTitle("Third-Party Services")
                    Text(
                        "CaptionMate uses WhisperKit for speech recognition, which processes all data locally on your device. No data is sent to external servers for transcription."
                    )

                    SectionTitle("Your Rights")
                    Text(
                        "Since we don't collect personal data, there is no data to request, modify, or delete. All processing occurs locally on your device, and you have complete control over your files and generated subtitles."
                    )

                    SectionTitle("Contact")
                    Text(
                        "If you have any questions about this Privacy Policy, please contact: parfume407@gmail.com"
                    )
                }
            }
            .padding()
        }
    }
}

// MARK: - Third Party Notices

struct ThirdPartyNoticesView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Third Party Notices")
                    .font(.title.bold())
                    .padding(.bottom, 8)

                Text(
                    "The following sets forth attribution notices for third party software that may be contained in portions of this CaptionMate product."
                )
                .padding(.bottom, 16)

                SectionTitle("MIT License")
                Text(
                    "The following components are licensed under the MIT license reproduced below."
                )

                VStack(alignment: .leading, spacing: 12) {
                    LibraryInfo(
                        name: "1. Whisper",
                        license: "MIT License",
                        copyright: "Copyright (c) 2022 OpenAI",
                        url: "https://github.com/openai/whisper"
                    )

                    Divider()

                    LibraryInfo(
                        name: "2. WhisperKit",
                        license: "MIT License",
                        copyright: "Copyright (c) 2024 argmax, inc.",
                        url: "https://github.com/argmaxinc/WhisperKit"
                    )
                }
                .padding()
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(8)

                Text(mitLicenseText)
                    .font(.caption)
                    .padding()
                    .background(Color.secondary.opacity(0.05))
                    .cornerRadius(8)

                Divider()
                    .padding(.vertical)

                Text("© 2025 Harrison Cho. All rights reserved.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
    }

    private var mitLicenseText: String {
        """
        The MIT License (MIT)

        Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

        The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

        THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
        """
    }
}

// MARK: - Security Policy

struct SecurityPolicyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Security Policy")
                    .font(.title.bold())
                    .padding(.bottom, 8)

                SectionTitle("Reporting Security Vulnerabilities")
                Text("Please use parfume407@gmail.com to report security vulnerabilities.")

                SectionTitle("Our Process")
                Text(
                    "We use parfume407@gmail.com for our intake and triage. For valid issues we will do coordination and disclosure here on GitHub (including using a GitHub Security Advisory when necessary)."
                )

                SectionTitle("Response Time")
                Text(
                    "We will process your report within a day, and respond within a week (although it will depend on the severity of your report)."
                )

                SectionTitle("Supported Versions")
                Text(
                    "We release security updates for the latest version of CaptionMate. Please ensure you're using the most recent version available on the App Store."
                )

                SectionTitle("Security Best Practices")
                VStack(alignment: .leading, spacing: 8) {
                    BulletPoint("All processing is done locally on your device")
                    BulletPoint("No user data is transmitted to external servers")
                    BulletPoint("App Sandbox and Hardened Runtime are enabled")
                    BulletPoint("Only user-selected files are accessed")
                    BulletPoint("Network access is limited to model downloads only")
                }
            }
            .padding()
        }
    }
}

// MARK: - License

struct LicenseView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Apache License 2.0")
                    .font(.title.bold())
                    .padding(.bottom, 8)

                Text(apacheLicenseText)
                    .font(.caption)
                    .padding()
                    .background(Color.secondary.opacity(0.05))
                    .cornerRadius(8)
            }
            .padding()
        }
    }

    private var apacheLicenseText: String {
        """
        Apache License
        Version 2.0, January 2004
        http://www.apache.org/licenses/

        Copyright 2025 Harrison Cho

        Licensed under the Apache License, Version 2.0 (the "License");
        you may not use this file except in compliance with the License.
        You may obtain a copy of the License at

            http://www.apache.org/licenses/LICENSE-2.0

        Unless required by applicable law or agreed to in writing, software
        distributed under the License is distributed on an "AS IS" BASIS,
        WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
        See the License for the specific language governing permissions and
        limitations under the License.

        TERMS AND CONDITIONS FOR USE, REPRODUCTION, AND DISTRIBUTION

        1. Definitions.

        "License" shall mean the terms and conditions for use, reproduction, and distribution as defined by Sections 1 through 9 of this document.

        "Licensor" shall mean the copyright owner or entity authorized by the copyright owner that is granting the License.

        "Work" shall mean the work of authorship, whether in Source or Object form, made available under the License.

        2. Grant of Copyright License. Subject to the terms and conditions of this License, each Contributor hereby grants to You a perpetual, worldwide, non-exclusive, no-charge, royalty-free, irrevocable copyright license to reproduce, prepare Derivative Works of, publicly display, publicly perform, sublicense, and distribute the Work and such Derivative Works in Source or Object form.

        3. Grant of Patent License. Subject to the terms and conditions of this License, each Contributor hereby grants to You a perpetual, worldwide, non-exclusive, no-charge, royalty-free, irrevocable (except as stated in this section) patent license to make, have made, use, offer to sell, sell, import, and otherwise transfer the Work.

        For the full license text, please visit: http://www.apache.org/licenses/LICENSE-2.0
        """
    }
}

// MARK: - Helper Views

struct SectionTitle: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.headline)
            .padding(.top, 8)
    }
}

struct LibraryInfo: View {
    let name: String
    let license: String
    let copyright: String
    let url: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(name)
                .font(.subheadline.weight(.semibold))
            Text("License: \(license)")
                .font(.caption)
            Text(copyright)
                .font(.caption)
            Link("Download Site: \(url)", destination: URL(string: url)!)
                .font(.caption)
        }
    }
}

struct BulletPoint: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
            Text(text)
        }
    }
}

#Preview {
    LegalView()
}
