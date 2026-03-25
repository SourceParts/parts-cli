// swift-tools-version: 5.10
import PackageDescription

// libgerbv include paths (gerbv + cairo + glib + gtk2 headers)
let gerbvCFlags: [String] = [
    "-I/opt/homebrew/Cellar/gerbv/2.11.1/include/gerbv",
    "-I/opt/homebrew/Cellar/cairo/1.18.4/include/cairo",
    "-I/opt/homebrew/Cellar/cairo/1.18.4/include",
    "-I/opt/homebrew/Cellar/glib/2.88.0/include/glib-2.0",
    "-I/opt/homebrew/Cellar/glib/2.88.0/lib/glib-2.0/include",
    "-I/opt/homebrew/Cellar/glib/2.88.0/include",
    "-I/opt/homebrew/Cellar/gtk+/2.24.33_2/include/gtk-2.0",
    "-I/opt/homebrew/Cellar/gtk+/2.24.33_2/lib/gtk-2.0/include",
    "-I/opt/homebrew/Cellar/at-spi2-core/2.60.0/include/atk-1.0",
    "-I/opt/homebrew/Cellar/harfbuzz/13.2.1/include/harfbuzz",
    "-I/opt/homebrew/Cellar/pango/1.57.0_2/include/pango-1.0",
    "-I/opt/homebrew/Cellar/fribidi/1.0.16/include/fribidi",
    "-I/opt/homebrew/Cellar/fontconfig/2.17.1/include",
    "-I/opt/homebrew/Cellar/pixman/0.46.4/include/pixman-1",
    "-I/opt/homebrew/include/gdk-pixbuf-2.0",
    "-I/opt/homebrew/opt/freetype/include/freetype2",
    "-I/opt/homebrew/opt/libpng/include/libpng16",
    "-I/opt/homebrew/Cellar/libx11/1.8.13/include",
    "-I/opt/homebrew/Cellar/libxcb/1.17.0/include",
    "-I/opt/homebrew/Cellar/libxau/1.0.12/include",
    "-I/opt/homebrew/Cellar/libxdmcp/1.1.5/include",
    "-I/opt/homebrew/Cellar/libxext/1.3.7/include",
    "-I/opt/homebrew/Cellar/libxrender/0.9.12/include",
    "-I/opt/homebrew/Cellar/xorgproto/2025.1/include",
    "-I/opt/homebrew/Cellar/libthai/0.1.30/include",
    "-I/opt/homebrew/Cellar/libdatrie/0.2.14/include",
    "-I/opt/homebrew/Cellar/pcre2/10.47_1/include",
    "-I/opt/homebrew/opt/gettext/include",
    "-I/opt/homebrew/opt/libtiff/include",
    "-I/opt/homebrew/opt/zstd/include",
    "-I/opt/homebrew/Cellar/xz/5.8.2/include",
    "-I/opt/homebrew/opt/jpeg-turbo/include",
]

let gerbvLinkFlags: [String] = [
    "-L/opt/homebrew/Cellar/gerbv/2.11.1/lib",
    "-L/opt/homebrew/Cellar/cairo/1.18.4/lib",
    "-L/opt/homebrew/Cellar/glib/2.88.0/lib",
    "-L/opt/homebrew/lib",
    "-lgerbv",
    "-lcairo",
    "-lglib-2.0",
    "-lgobject-2.0",
]

let package = Package(
    name: "PartsStudio",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    targets: [
        .systemLibrary(
            name: "CGerbv",
            path: "CGerbv"
        ),
        .executableTarget(
            name: "PartsStudio",
            dependencies: [
                .target(name: "CGerbv", condition: .when(platforms: [.macOS])),
            ],
            path: "PartsStudio",
            resources: [
                .process("Resources/soc_info_table.json"),
                .copy("FEL"),
            ],
            cSettings: [
                .unsafeFlags(gerbvCFlags, .when(platforms: [.macOS])),
            ],
            linkerSettings: [
                .linkedFramework("IOKit", .when(platforms: [.macOS])),
                .linkedFramework("Speech"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreBluetooth"),
                .linkedFramework("SceneKit"),
                .linkedFramework("ModelIO"),
                .unsafeFlags(gerbvLinkFlags, .when(platforms: [.macOS])),
            ]
        )
    ]
)
