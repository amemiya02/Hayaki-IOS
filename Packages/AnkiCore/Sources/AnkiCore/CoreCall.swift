import AnkiProto
import Foundation

/// One call into the core: which method, with which request, and the type of
/// its response. Every method of the core has a generated factory, such as
/// `CoreCall.getDeckNames(_:)`, so calls are never numbered by hand.
///
/// Run a call with `CoreClient.perform(_:)`, or with `CoreClient.start(_:)`
/// when it is a long operation whose progress you want to show or which the
/// learner may cancel.
public struct CoreCall<Response: SwiftProtobuf.Message>: Sendable {
    public let method: CoreMethod
    let request: any SwiftProtobuf.Message

    init(_ method: CoreMethod, _ request: some SwiftProtobuf.Message) {
        self.method = method
        self.request = request
    }

    func encodedRequest() -> Result<Data, CoreError> {
        do {
            return .success(try request.serializedData())
        } catch {
            return .failure(CoreError(kind: .protoError, message: String(
                localized: "Could not encode \(String(describing: method)): \(error.localizedDescription)", bundle: .module
            )))
        }
    }

    func decode(_ bytes: Data) -> Result<Response, CoreError> {
        do {
            return .success(try Response(serializedBytes: bytes))
        } catch {
            return .failure(CoreError(kind: .protoError, message: String(
                localized: "Could not decode \(String(describing: method)): \(error.localizedDescription)", bundle: .module
            )))
        }
    }
}
