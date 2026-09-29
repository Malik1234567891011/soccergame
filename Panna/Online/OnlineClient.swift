import Foundation
import PannaCore

/// Placeholder until the online stack lands (see Server/).
@MainActor
final class OnlineClient: ObservableObject {
    enum Status: Equatable { case offline, connecting, online, queued(String), matched }
    @Published var status: Status = .offline
}
