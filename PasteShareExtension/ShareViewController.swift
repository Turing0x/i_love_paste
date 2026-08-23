import PasteCore
import SwiftUI
import UIKit

/// Punto de entrada de la Share Extension.
///
/// Es un `UIHostingController` y no un `SLComposeServiceViewController`: la
/// interfaz de ese último es la de "publicar un post" —destinatario, texto,
/// cuenta— y aquí no se publica nada, se guarda.
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()

        let providers = (extensionContext?.inputItems as? [NSExtensionItem])?
            .flatMap { $0.attachments ?? [] } ?? []

        let view = ShareView(
            providers: providers,
            onFinish: { [weak self] in
                self?.extensionContext?.completeRequest(returningItems: nil)
            },
            onCancel: { [weak self] in
                self?.extensionContext?.cancelRequest(
                    withError: CocoaError(.userCancelled)
                )
            }
        )

        let host = UIHostingController(rootView: view)
        addChild(host)
        host.view.frame = self.view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        self.view.addSubview(host.view)
        host.didMove(toParent: self)
    }
}
