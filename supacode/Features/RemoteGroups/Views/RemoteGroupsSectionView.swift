import ComposableArchitecture
import SwiftUI

struct RemoteGroupsSectionView: View {
  @Bindable var store: StoreOf<RemoteGroupsFeature>

  var body: some View {
    Section {
      if store.endpoints.isEmpty {
        Text("No remote endpoints")
          .foregroundStyle(.secondary)
      } else {
        ForEach(store.endpoints) { endpoint in
          endpointRow(endpoint)
            .tag(SidebarSelection.remoteEndpoint(endpoint.id))
            .contextMenu {
              Button("Refresh Groups") {
                store.send(.fetchEndpointSessions(endpoint.id))
              }
              .help("Refresh groups")
            }

          if let groups = store.groupsByEndpointID[endpoint.id], !groups.isEmpty {
            ForEach(groups) { groupRef in
              groupRow(groupRef: groupRef)
                .tag(
                  SidebarSelection.remoteGroup(
                    endpointID: endpoint.id,
                    group: groupRef.group
                  )
                )
            }
          }
        }
      }
    } header: {
      Text("Remote Groups")
    }
  }

  @ViewBuilder
  private func endpointRow(_ endpoint: RemoteEndpoint) -> some View {
    let host = endpoint.baseURL.host(percentEncoded: false) ?? endpoint.baseURL.absoluteString
    let errorMessage = store.errorByEndpointID[endpoint.id]

    HStack(spacing: 8) {
      Image(systemName: "network")
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 2) {
        Text(host)
          .lineLimit(1)
        Text(endpoint.baseURL.absoluteString)
          .font(.footnote.monospaced())
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .truncationMode(.middle)
      }
      Spacer()
      if store.loadingEndpointIDs.contains(endpoint.id) {
        ProgressView()
          .controlSize(.small)
      } else if let errorMessage {
        Image(systemName: "exclamationmark.triangle.fill")
          .foregroundStyle(.yellow)
          .accessibilityLabel("Endpoint error")
          .help(errorMessage)
      }
    }
    .contentShape(Rectangle())
    .help(endpoint.baseURL.absoluteString)
  }

  private func groupRow(groupRef: RemoteGroupRef) -> some View {
    HStack(spacing: 8) {
      Image(systemName: "rectangle.3.group")
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
      Text(groupRef.group)
        .lineLimit(1)
      Spacer()
      Text("\(groupRef.sessionCount)")
        .foregroundStyle(.secondary)
        .monospacedDigit()
    }
    .padding(.leading, 18)
    .contentShape(Rectangle())
    .help("Open \(groupRef.group)")
  }
}
