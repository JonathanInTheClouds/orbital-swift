//
//  ContainersView.swift
//  Orbital
//
//  Created by Jonathan on 4/14/26.
//

import SwiftUI

struct ContainersView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "No Containers",
                systemImage: "shippingbox",
                description: Text("Containers across your servers will appear here.")
            )
            .navigationTitle("Containers")
        }
    }
}

#Preview {
    ContainersView()
}
