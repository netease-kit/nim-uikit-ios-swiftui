// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import SwiftUI

extension View {
    @MainActor
    func demoHidesTabBar() -> some View {
        toolbar(.hidden, for: .tabBar)
    }
}
