import Foundation

/// Almacén en disco para imágenes y ficheros.
///
/// Las imágenes no van dentro de la base de datos: una captura de pantalla pesa
/// varios megabytes y meterlas como BLOB haría que cualquier consulta del
/// historial arrastrase ese peso por el camino. En la fila solo queda la ruta.
public struct BlobStore: Sendable {
    /// Directorio raíz. Los blobs se reparten en subcarpetas por los dos
    /// primeros caracteres del hash, para no dejar decenas de miles de ficheros
    /// sueltos en un mismo directorio.
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    /// Guarda los datos bajo su hash y devuelve la ruta relativa.
    ///
    /// Si el blob ya existe no se reescribe: el nombre es el hash del contenido,
    /// así que un fichero con ese nombre ya contiene exactamente estos bytes.
    public func store(_ data: Data, hash: String) throws -> String {
        let relative = Self.relativePath(for: hash)
        let url = root.appendingPathComponent(relative)
        guard !FileManager.default.fileExists(atPath: url.path) else { return relative }

        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
        return relative
    }

    public func data(at relativePath: String) throws -> Data {
        try Data(contentsOf: url(for: relativePath))
    }

    public func url(for relativePath: String) -> URL {
        root.appendingPathComponent(relativePath)
    }

    /// Borra un blob. No es error que ya no esté.
    public func remove(at relativePath: String) throws {
        let url = url(for: relativePath)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    static func relativePath(for hash: String) -> String {
        // El hash llega con prefijo de tipo ("b:abcd..."); fuera, no vale como
        // nombre de fichero.
        let clean = hash.split(separator: ":").last.map(String.init) ?? hash
        guard clean.count > 2 else { return clean }
        let bucket = String(clean.prefix(2))
        return "\(bucket)/\(clean)"
    }
}
