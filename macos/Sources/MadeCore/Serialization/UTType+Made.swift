import UniformTypeIdentifiers

extension UTType {
    /// Native document file format package (.made) Uniform Type Identifier.
    public static let madeDocument = UTType(exportedAs: "com.made.cad.document", conformingTo: .package)

    /// Standard stereolithography 3D model format (.stl).
    public static let stl = UTType(importedAs: "public.standard-tesselated-geometry-format", conformingTo: .data)

    /// 3D Manufacturing Format (.3mf) Uniform Type Identifier.
    public static let threeMF = UTType(importedAs: "org.3mf.3mf", conformingTo: .data)

    /// AutoCAD Drawing Interchange Format (.dxf) Uniform Type Identifier.
    public static let dxf = UTType(filenameExtension: "dxf", conformingTo: .plainText)
        ?? UTType(importedAs: "com.autodesk.dxf", conformingTo: .plainText)

    /// Standard VTK XML UnstructuredGrid 3D finite element result format (.vtu).
    public static let vtu = UTType(filenameExtension: "vtu", conformingTo: .xml)
        ?? UTType(importedAs: "org.vtk.vtu", conformingTo: .xml)
}
