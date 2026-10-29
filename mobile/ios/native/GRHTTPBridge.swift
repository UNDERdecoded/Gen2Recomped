// Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
import Foundation
import CoreFoundation

enum GRHTTPFailure: Error { case invalid }
struct GRHTTPRequest {
    let url: URL, method: String, agent: String, accept: String, mime: String
    let seconds: Double, maximum: Int, secure: Bool, discard: Bool, body: Data?
    static func text(_ value: Any?, maximum: Int) throws -> String {
        guard let text=value as? String, text.utf8.count<=maximum,
              !text.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
        else { throw GRHTTPFailure.invalid }
        return text
    }
    static func number(_ value: Any?, minimum: Double, maximum: Double) throws -> Double {
        guard let n=value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(),
              n.doubleValue.isFinite, n.doubleValue>=minimum, n.doubleValue<=maximum
        else { throw GRHTTPFailure.invalid }
        return n.doubleValue
    }
    static func flag(_ value: Any?) throws -> Bool {
        guard let n=value as? NSNumber, CFGetTypeID(n)==CFBooleanGetTypeID() else { throw GRHTTPFailure.invalid }
        return n.boolValue
    }
    static func allowed(_ url: URL, secure: Bool) -> Bool {
        guard let scheme=url.scheme?.lowercased(), let host=url.host, !host.isEmpty,
              url.absoluteString.utf8.count<=8192,
              !url.absoluteString.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.contains($0) })
        else { return false }
        return scheme=="https" || (!secure && scheme=="http")
    }
    init(_ json: String) throws {
        guard json.utf8.count<=1024*1024, let data=json.data(using:.utf8),
              let doc=try JSONSerialization.jsonObject(with:data) as? [String:Any]
        else { throw GRHTTPFailure.invalid }
        guard try Self.number(doc["boundedVersion"],minimum:1,maximum:1)==1 else { throw GRHTTPFailure.invalid }
        method=try Self.text(doc["method"],maximum:4)
        guard method=="GET" || method=="POST" else { throw GRHTTPFailure.invalid }
        secure=try Self.flag(doc["httpsOnly"]) || method=="POST"
        discard=try Self.flag(doc["discardBody"])
        let address=try Self.text(doc["url"],maximum:8192)
        guard !address.unicodeScalars.contains(where:{CharacterSet.whitespacesAndNewlines.contains($0)}),
              let target=URL(string:address), Self.allowed(target,secure:secure)
        else { throw GRHTTPFailure.invalid }
        url=target
        agent=try Self.text(doc["userAgent"],maximum:512);accept=try Self.text(doc["accept"],maximum:512)
        mime=try Self.text(doc["contentType"],maximum:128)
        seconds=try Self.number(doc["maxSeconds"],minimum:0.001,maximum:30)
        let bytes=try Self.number(doc["maxBytes"],minimum:1,maximum:16*1024*1024)
        guard bytes.rounded(.down)==bytes else { throw GRHTTPFailure.invalid };maximum=Int(bytes)
        if method=="POST" {
            let encoded=try Self.text(doc["bodyBase64"],maximum:((512*1024+2)/3)*4)
            guard let decoded=Data(base64Encoded:encoded), decoded.count<=512*1024 else { throw GRHTTPFailure.invalid }
            body=decoded
        } else { body=nil }
    }
}

private final class GRHTTPTransfer: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    let request: GRHTTPRequest
    let done=DispatchSemaphore(value:0)
    private let gate=NSLock()
    private var result: [String:Any]?
    private var bytes=Data()
    private var status: Int?
    private var declared: Int64 = -1
    private var redirects=0
    private var released=false
    private let release: () -> Void
    init(_ request: GRHTTPRequest, release: @escaping () -> Void) { self.request=request;self.release=release }
    func finish(error: Bool) {
        gate.lock()
        if result != nil { gate.unlock();return }
        var value: [String:Any]=[:]
        if let code=status { value["status"]=code }
        if error {value["error"]="bounded HTTP request failed"}
        else if !request.discard {value["bodyBase64"]=bytes.base64EncodedString()}
        result=value;gate.unlock();done.signal()
    }
    func take() -> [String:Any] { gate.lock();defer{gate.unlock()};return result ?? ["error":"bounded HTTP request failed"] }
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        gate.lock()
        let allowed=request.method=="GET" && redirects<5 && result==nil &&
            newRequest.url.map{GRHTTPRequest.allowed($0,secure:request.secure)}==true
        if allowed {redirects+=1} else {status=response.statusCode}
        gate.unlock()
        if allowed {
            var next=newRequest;next.setValue(request.agent,forHTTPHeaderField:"User-Agent")
            next.setValue(request.accept,forHTTPHeaderField:"Accept")
            next.setValue("identity",forHTTPHeaderField:"Accept-Encoding")
            completionHandler(next)
        } else {finish(error:true);completionHandler(nil)}
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let http=response as? HTTPURLResponse else {finish(error:true);completionHandler(.cancel);return}
        gate.lock();status=http.statusCode;declared=response.expectedContentLength
        let valid=result==nil && (200..<300).contains(http.statusCode)
        let oversized=declared>Int64(request.maximum)
        gate.unlock()
        if !valid || (!request.discard && oversized) {finish(error:true);completionHandler(.cancel)}
        else if request.discard {finish(error:false);completionHandler(.cancel)}
        else {completionHandler(.allow)}
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        gate.lock()
        if result != nil {gate.unlock();return}
        let oversized=data.count>request.maximum-bytes.count
        if !oversized {bytes.append(data)}
        gate.unlock()
        if oversized {finish(error:true);dataTask.cancel()}
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        gate.lock()
        let incomplete=declared>=0 && declared != Int64(bytes.count)
        let firstRelease = !released;released=true
        gate.unlock()
        finish(error:error != nil || incomplete)
        // A cancelled platform task retains its native slot until this terminal callback.
        if firstRelease {release()}
    }
}

enum GRBoundedHTTP {
    private static let pool=NSLock()
    private static var active=0
    private static func acquire() -> Bool {pool.lock();defer{pool.unlock()};if active>=16{return false};active+=1;return true}
    private static func release() {pool.lock();active-=1;pool.unlock()}
    static func perform(_ json: String, configuration: URLSessionConfiguration? = nil) -> String {
        let failure="{\"error\":\"bounded HTTP request failed\"}"
        guard let request=try? GRHTTPRequest(json), acquire() else {return failure}
        let transfer=GRHTTPTransfer(request,release:release)
        let config=configuration ?? URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest=request.seconds;config.timeoutIntervalForResource=request.seconds
        config.httpShouldSetCookies=false;config.httpCookieStorage=nil;config.urlCredentialStorage=nil
        config.urlCache=nil;config.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session=URLSession(configuration:config,delegate:transfer,delegateQueue:nil)
        var message=URLRequest(url:request.url,timeoutInterval:request.seconds)
        message.httpMethod=request.method;message.httpBody=request.body
        message.setValue(request.agent,forHTTPHeaderField:"User-Agent")
        message.setValue(request.accept,forHTTPHeaderField:"Accept")
        message.setValue("identity",forHTTPHeaderField:"Accept-Encoding")
        if request.body != nil {message.setValue(request.mime,forHTTPHeaderField:"Content-Type")}
        let task=session.dataTask(with:message);task.resume()
        if transfer.done.wait(timeout:.now()+request.seconds) == .timedOut {transfer.finish(error:true);task.cancel()}
        session.invalidateAndCancel()
        guard let data=try? JSONSerialization.data(withJSONObject:transfer.take()),
              let value=String(data:data,encoding:.utf8) else {return failure}
        return value
    }
}

@objc(GRHTTPBridge)
public final class GRHTTPBridge: NSObject {
    @objc(requestWithJSON:)
    public static func request(json: UnsafePointer<CChar>?) -> NSString {
        guard let json=json, let value=String(validatingUTF8:json) else {return "{\"error\":\"invalid bounded request\"}"}
        return GRBoundedHTTP.perform(value) as NSString
    }
}
