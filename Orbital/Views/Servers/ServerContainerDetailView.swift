//
//  ServerContainerDetailView.swift
//  Orbital
//
//  Created by Codex on 4/14/26.
//

import SwiftUI

struct ServerContainerDetailView: View {
    let server: Server
    let runtime: ContainerRuntimeKind
    let container: ContainerStatusSnapshot

    var body: some View {
        ContainerDetailView(
            server: server,
            runtime: runtime,
            containerName: container.name,
            initialContainer: container
        )
    }
}
