import SwiftUI

struct GoogleUserProfileView: View {
    let userInfo: GoogleUserProfile

    var body: some View {
        VStack {
            if let picture = userInfo.picture, let url = URL(string: picture) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 50, height: 50)
                        .clipShape(Circle())
                } placeholder: {
                    ProgressView()
                        .frame(width: 50, height: 50)
                }
            }
            Text(userInfo.name)
            Text(userInfo.email)
        }
    }
}
