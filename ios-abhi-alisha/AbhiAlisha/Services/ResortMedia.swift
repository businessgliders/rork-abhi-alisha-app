import Foundation

/// The resort photography and map the couple publish on their own booking page,
/// kept here so the app shows exactly the same pictures guests already know.
enum ResortMedia {
    /// The lead photograph on the couple's booking page.
    private static let hero =
        "https://media.base44.com/images/public/69e98bd1f9ddf4a4cfd0d8f4/b66f3a88e_26192371_ImageLargeWidth.png"

    /// The resort's rooms and grounds, in the couple's own order.
    private static let gallery: [String] = [
        "https://media.base44.com/images/public/69e98bd1f9ddf4a4cfd0d8f4/e1b774c20_6839b4ba0bb6fa705675fa9c_23339176_ImageLargeWidth.png",
        "https://media.base44.com/images/public/69e98bd1f9ddf4a4cfd0d8f4/2620d4db7_6839b4ba4cbe81ef15263cd0_25070669_ImageLargeWidth.png",
        "https://media.base44.com/images/public/69e98bd1f9ddf4a4cfd0d8f4/5f8f14aaa_6839b4ba930bf146a9c98e40_23339313_ImageLargeWidth.png",
        "https://media.base44.com/images/public/69e98bd1f9ddf4a4cfd0d8f4/2474c5bfe_6839b4baaf12147809f685a6_23339314_ImageLargeWidth.png",
        "https://media.base44.com/images/public/69e98bd1f9ddf4a4cfd0d8f4/a749bb98a_68255f3dc83d76ef2ed7ff81_23169391_ImageLargeWidth-5123689jpeg.png",
        "https://media.base44.com/images/public/69e98bd1f9ddf4a4cfd0d8f4/849c73c8a_6824df3fe1490d0c97648e04_23779579_ImageLargeWidth-5123689.png",
        "https://media.base44.com/images/public/69e98bd1f9ddf4a4cfd0d8f4/63eda76ed_6824df3ee2834ac7b5564d1b_23779543_ImageLargeWidth-5123689_1.png",
        "https://media.base44.com/images/public/69e98bd1f9ddf4a4cfd0d8f4/17b97ca2e_6824df3d12c67f409a412b0e_23784154_ImageLargeWidth-5123689_1.png",
        "https://media.base44.com/images/public/69e98bd1f9ddf4a4cfd0d8f4/85f774885_6824df3ebd7c90280a1013f6_23992183_ImageLargeWidth-5123727.jpg",
        "https://media.base44.com/images/public/69e98bd1f9ddf4a4cfd0d8f4/a64cdcefd_6824df3e7c3e6050568f9a78_23169456_ImageLargeWidth-5123689.jpg",
        "https://media.base44.com/images/public/69e98bd1f9ddf4a4cfd0d8f4/45036928b_6824df3ef66f1087480fc29d_23169403_ImageLargeWidth-5123689.jpg",
        "https://media.base44.com/images/public/69e98bd1f9ddf4a4cfd0d8f4/359765981_6824df3ebfd022e0ef3a9b27_23169379_ImageLargeWidth-5123689.jpg"
    ]

    /// Every resort photograph, hero first.
    static let photos: [URL] = ([hero] + gallery).compactMap(URL.init(string:))
}
