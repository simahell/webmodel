open util/ordering[Time]

abstract sig Principal {
	servers : set NetworkEndpoint,
}

fact DNSIsDisjointAmongstPrincipals {
	all disj p1,p2 : Principal | no (p1.servers & p2.servers)
}

sig Time {}
sig Token {}

pred happensBeforeOrdering[first:Event,second:Event]{
	second.current in first.current.*next
}

fact Traces{
	all t:Time | one e:Event | t = e.current
}

sig NetworkEndpoint{cache : lone Cache}

abstract sig Event {
	current : one Time
}

abstract sig NetworkEvent extends Event {
	from: NetworkEndpoint,
	to: NetworkEndpoint
}

abstract sig HTTPHeader {}
abstract sig HTTPResponseHeader extends HTTPHeader{}
abstract sig HTTPRequestHeader extends HTTPHeader{}
abstract sig HTTPGeneralHeader extends HTTPHeader{}
abstract sig HTTPEntityHeader extends HTTPHeader{}
abstract sig Status  {}
abstract sig RedirectionStatus extends Status {}

fact noOrphanedHeaders {
	all h:HTTPRequestHeader|some req:HTTPRequest|h in req.headers
	all h:HTTPResponseHeader|some resp:HTTPResponse|h in resp.headers
	all h:HTTPGeneralHeader|some req:HTTPRequest, resp:HTTPResponse|h in req.headers or h in resp.headers
	all h:HTTPEntityHeader|some req:HTTPRequest, resp:HTTPResponse|h in req.headers or h in resp.headers
}

abstract sig HTTPEvent extends NetworkEvent {
	headers: set HTTPHeader,
	uri : one Uri
}

sig Uri extends Token{}

sig HTTPRequest extends HTTPEvent {}

sig HTTPResponse extends HTTPEvent {
	reuse: lone CacheStatus
}

enum CacheStatus{OK, NG}

fact reusePossibility{
	all res:HTTPResponse |
		res in Cache.stored implies #(res.reuse)=1
		else #(res.reuse)=0
}

//check pair of request and response
fact ReqToRes{
	all req:HTTPRequest | some res:HTTPResponse | req.uri = res.uri and res.current in req.current.*next
	all res:HTTPResponse | some req:HTTPRequest | req.uri = res.uri and req.current in (Time - res.current.*next)
}

/****************************

Cache Definitions

****************************/
sig IfModifiedSinceHeader extends HTTPRequestHeader{}
sig IfNoneMatchHeader extends HTTPRequestHeader{}
sig ETagHeader extends HTTPResponseHeader{}
sig LastModifiedHeader extends HTTPResponseHeader{}
sig AgeHeader extends HTTPResponseHeader{}
sig CacheControlHeader extends HTTPGeneralHeader{options : set CacheOption}
sig DateHeader extends HTTPGeneralHeader{}
sig ExpiresHeader extends HTTPEntityHeader{}

abstract sig CacheOption{}
abstract sig ResponseCacheOption extends CacheOption{}
sig NoCache,NoStore,NoTransform extends CacheOption{}
sig Maxage,SMaxage,Private,Public extends ResponseCacheOption{}

abstract sig Cache{
	stored: set HTTPResponse,
}{
	all res:HTTPResponse |
		res in stored implies {
			no op:NoStore | op in res.headers.options
			no h:AgeHeader | h in res.headers
		}
}

sig PrivateCache extends Cache{}{
	all res:HTTPResponse |
		res in stored implies
			((some op:Maxage | op in res.headers.options) or
			(some d:DateHeader, e:ExpiresHeader | d in res.headers and e in res.headers))
}

sig PublicCache extends Cache{}{
	no res:HTTPResponse |
		res in stored implies
			no h:CacheControlHeader | h in res.headers and (Private in h.options)

	all res:HTTPResponse |
		res in stored implies
			((some op:SMaxage | op in HTTPResponse.headers.options) or
			(some op:Maxage | op in HTTPResponse.headers.options) or
			(some d:DateHeader, e:ExpiresHeader | d in HTTPResponse.headers and e in HTTPResponse.headers))
}

fact noOrphanedCaches {
	all c:Cache |
		one e:NetworkEndpoint | c = e.cache
}

fact noMultipleCaches {
	no disj e1, e2:NetworkEndpoint | e1.cache = e2.cache
}

//for reuse of response
fact reuseCache{
	all res:HTTPResponse |
		res in Cache.stored implies
			one origin_res:HTTPResponse |
				{
					origin_res.reuse = OK
					equalResponse[res, origin_res]
					res.current in origin_res.current.*next
				}
}

//for confirming identify of two responses
//judge by headers
pred equalResponse[tar:HTTPResponse, res:HTTPResponse]{
	all h:HTTPHeader |
			(h in tar.headers implies h in res.headers) and (h in res.headers implies h in tar.headers)
}

pred checkExpiration[res:HTTPResponse]{
	res.reuse = OK
}

/*
pred validationResponse[res:HTTPResponse]{

}
*/

fact LimitHeader{
	all h:HTTPHeader | h in HTTPResponse.headers or h in HTTPRequest.headers
	all c:CacheOption | c in CacheControlHeader.options
}

run {
	#PrivateCache = 1
	#PublicCache = 0
	#stored > 0
	#HTTPResponse > 0
	#HTTPRequest > 0

	#IfModifiedSinceHeader = 0
	#IfNoneMatchHeader = 0
	#ETagHeader = 0
	#LastModifiedHeader = 0
	#AgeHeader = 0
	#DateHeader = 0
	#ExpiresHeader = 0
}