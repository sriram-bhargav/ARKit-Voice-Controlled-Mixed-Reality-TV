import UIKit

public class Youtube: NSObject {
  // Follow this (https://github.com/iphoting/youtube-dl-api-server-heroku) to bring up ready-for-Heroku youtube-dl REST API server
  static let infoURL = "https://{YOUR_YOUTUBE_DL_APP_NAME}.herokuapp.com/api/info?url=http://www.youtube.com/watch?v="
  static let params = "&format=mp4"
  static var userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_8_2) AppleWebKit/537.4 (KHTML, like Gecko) Chrome/22.0.1229.79 Safari/537.4"

  public static func h264videosWithYoutubeID(youtubeID: String) -> String {
    let urlString = String(format: "%@%@%@", infoURL, youtubeID, params) as String
    let url = NSURL(string: urlString)!
    let request = NSMutableURLRequest(url: url as URL)
    request.timeoutInterval = 5.0
    request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
    request.httpMethod = "GET"
    var responseString: String = ""
    let session = URLSession(configuration: URLSessionConfiguration.default)
    let group = DispatchGroup()
    group.enter()
    session.dataTask(with: request as URLRequest, completionHandler: { (data, response, error) -> Void in
        do {
            print(request.url!.absoluteString)
            if let jsonResult = try JSONSerialization.jsonObject(with: data!, options: []) as? [String : Any] {
                let info = jsonResult["info"] as! [String: Any]
                responseString = info["url"] as! String
            }
        }
        catch {
            print("json error: \(error)")
        }
        group.leave()
    }).resume()
    let _ = group.wait(timeout: DispatchTime.distantFuture)
    return responseString
  }
}
