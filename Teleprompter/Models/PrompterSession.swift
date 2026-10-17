import Observation

/// Which script is open in the full-screen prompter, shared by the library UI and the web remote.
@MainActor
@Observable
final class PrompterSession {
    /// Setting this presents the prompter; setting it to nil closes it.
    var activeScript: Script?

    /// The running prompter's engine, registered by `PrompterView` while it is on screen.
    @ObservationIgnored weak var engine: PrompterEngine?
}
