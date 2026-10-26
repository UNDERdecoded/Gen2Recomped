// Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
import Foundation
final class HTTPFixture: URLProtocol {
    static let gate=NSLock()
    static var seen: [URLRequest]=[]
    static var bodies: [Data?]=[]
    private var stopped=false
    private let state=NSLock()
    override class func canInit(with request: URLRequest) -> Bool {request.url?.host=="fixture.invalid"}
    override class func canonicalRequest(for request: URLRequest) -> URLRequest {request}
    override func stopLoading() {state.lock();stopped=true;state.unlock()}
    override func startLoading() {
        var body=request.httpBody
        if body==nil, let stream=request.httpBodyStream {
            stream.open();defer{stream.close()}
            var collected=Data();var chunk=[UInt8](repeating:0,count:4096)
            while true {let count=stream.read(&chunk,maxLength:chunk.count);if count<=0{break};collected.append(contentsOf:chunk.prefix(count))}
            body=collected
        }
        Self.gate.lock();Self.seen.append(request);Self.bodies.append(body);Self.gate.unlock()
        let path=request.url!.path
        if path=="/redirect-post" || path=="/redirect-get" || path=="/downgrade" {
            let target=URL(string:(path=="/downgrade" ? "http" : "https")+"://fixture.invalid/target")!
            var next=request;next.url=target
            let response=HTTPURLResponse(url:request.url!,statusCode:307,httpVersion:"HTTP/1.1",headerFields:["Location":target.absoluteString])!
            client?.urlProtocol(self,wasRedirectedTo:next,redirectResponse:response)
            return
        }
        if path=="/slow" {
            DispatchQueue.global().asyncAfter(deadline:.now()+0.8) {
                self.state.lock();let stopped=self.stopped;self.state.unlock()
                if !stopped {self.reply(Data([1,2,3]),length:3)}
            }
            return
        }
        if path=="/oversized" {reply(Data(repeating:1,count:100),length:100);return}
        if path=="/chunked" {reply(Data(repeating:2,count:100),length:nil);return}
        if path=="/partial" {reply(Data([1,2]),length:100);return}
        reply(path=="/post" ? Data("private server reply".utf8) : Data([0,255,13,10]),length:nil)
    }
    private func reply(_ bytes: Data,length: Int?) {
        let headers=length.map{["Content-Length":String($0)]} ?? [:]
        let response=HTTPURLResponse(url:request.url!,statusCode:200,httpVersion:"HTTP/1.1",headerFields:headers)!
        client?.urlProtocol(self,didReceive:response,cacheStoragePolicy:.notAllowed)
        client?.urlProtocol(self,didLoad:bytes);client?.urlProtocolDidFinishLoading(self)
    }
}
var checks=0
func check(_ ok: @autoclosure () -> Bool,_ label: String) {checks+=1;precondition(ok(),label)}
func wire(_ method: String="GET",_ path: String="/binary",_ extra: [String:Any]=[:]) -> String {
    var req: [String:Any] = ["boundedVersion":1,"method":method,"url":"https://fixture.invalid"+path,
      "httpsOnly":true,"discardBody":method=="POST","userAgent":"gen2recomp-mod/native_probe",
      "accept":"*/*","contentType":"text/plain; charset=utf-8","maxSeconds":1.0,"maxBytes":1024]
    if method=="POST" {req["bodyBase64"]=Data([0,255,13,10]).base64EncodedString()}
    for (key,value) in extra {req[key]=value}
    return String(data:try! JSONSerialization.data(withJSONObject:req),encoding:.utf8)!
}
func run(_ json: String) -> [String:Any] {
    let config=URLSessionConfiguration.ephemeral;config.protocolClasses=[HTTPFixture.self]
    let result=GRBoundedHTTP.perform(json,configuration:config)
    return try! JSONSerialization.jsonObject(with:Data(result.utf8)) as! [String:Any]
}
let binary=run(wire())
check((binary["status"] as? Int)==200,"GET status")
check(Data(base64Encoded:binary["bodyBase64"] as! String)==Data([0,255,13,10]),"binary reply preserved")
let post=run(wire("POST","/post"))
check((post["status"] as? Int)==200 && post["bodyBase64"]==nil && post["error"]==nil,"one-way POST discards reply")
HTTPFixture.gate.lock();let sent=HTTPFixture.seen.last!;let sentBody=HTTPFixture.bodies.last!;HTTPFixture.gate.unlock()
check(sent.httpMethod=="POST" && sentBody==Data([0,255,13,10]),"request bytes preserved")
check(sent.value(forHTTPHeaderField:"User-Agent")=="gen2recomp-mod/native_probe","fixed identity")
check(sent.value(forHTTPHeaderField:"Accept-Encoding")=="identity","no implicit transfer compression")
let redirected=run(wire("POST","/redirect-post"))
check(redirected["error"] != nil,"POST redirect refused")
HTTPFixture.gate.lock();let targets=HTTPFixture.seen.filter{$0.url?.path=="/target"}.count;HTTPFixture.gate.unlock()
check(targets==0,"POST is never forwarded to another destination")
let getRedirect=run(wire("GET","/redirect-get"))
check((getRedirect["status"] as? Int)==200,"GET follows allowed redirects")
check(run(wire("GET","/downgrade"))["error"] != nil,"HTTPS downgrade refused")
for path in ["/oversized","/chunked","/partial"] {
    let result=run(wire("GET",path,["maxBytes":path=="/partial" ? 1024 : 16]))
    check(result["error"] != nil && result["bodyBase64"]==nil,"bounded and complete response required")
}
let began=Date();let slow=run(wire("GET","/slow",["maxSeconds":0.1]))
check(slow["error"] != nil && Date().timeIntervalSince(began)<0.7,"absolute native deadline")
for change in [["boundedVersion":true],["maxBytes":true],["httpsOnly":1],["method":"DELETE"],["url":"file:///secret"],
    ["maxSeconds":31],["userAgent":"bad\nheader"],["method":"POST","url":"http://fixture.invalid/post"]] as [[String:Any]] {
    check(run(wire("GET","/binary",change))["error"] != nil,"invalid native wire refused")
}
print("Native HTTP Swift: \(checks) PASS; URLProtocol fixture, not physical TLS")
