//
//	declarrations.als (exisiting)
//

abstract sig HTTPHeader {}
abstract sig HTTPResponseHeader extends HTTPHeader{}{
	all h:this | h in HTTPResponse.headers
}
/*
abstract sig HTTPRequestHeader extends HTTPHeader{}{
	all h:this | h in HTTPRequest.headers
}
*/
abstract sig HTTPGeneralHeader extends HTTPHeader{}
//abstract sig HTTPEntityHeader extends HTTPHeader{}

abstract sig HTTPEvent{headers: set HTTPHeader}
lone sig HTTPResponse extends HTTPEvent{}
one sig HTTPRequest extends HTTPEvent{}

//
//	cache.als
//
abstract sig CacheOption{}
abstract sig RequestCacheOption extends CacheOption{}
abstract sig ResponseCacheOption extends CacheOption{}
/*
lone sig NoCache,NoStore,NoTransform extends CacheOption{}
lone sig OnlyIfCached extends RequestCacheOption{}
lone sig MaxStale,MinStale extends RequestCacheOption{time: one Int}
lone sig MustRevalidate,Public,Private,ProxyRevalidate extends ResponseCacheOption{}
lone sig Maxage,SMaxage extends ResponseCacheOption{time: one Int}
*/

lone sig NoCache,NoStore extends CacheOption{}
lone sig OnlyIfCached extends RequestCacheOption{}
lone sig MaxStale extends RequestCacheOption{time: one Int}{time > 0}
lone sig Private extends ResponseCacheOption{}
lone sig Maxage,SMaxage extends ResponseCacheOption{time: one Int}{time > 0}

sig AgeHeader extends HTTPResponseHeader{age : one Int}
{
	age > 0
}
sig CacheControlHeader extends HTTPGeneralHeader{options : set CacheOption}
sig DateHeader extends HTTPGeneralHeader{date : one Int}{date > 0}
sig ExpiresHeader extends HTTPGeneralHeader{expire : one Int}{expire > 0}

lone abstract sig Cache{
	stored: lone HTTPResponse,
	current: one Int,
	reqtime: one Int,
	restime: one Int
/*	a: one Int,
	b: one Int,
	c: one Int,
	d: one Int,
	e: one Int,
	f: one Int,
	g: one Int*/
}{
	current > 0
	reqtime > 0
	restime > 0
	#stored  = 1 implies current > restime and restime > reqtime

	#stored>0 implies no NoStore	//for NoStore
	#stored>0 implies #AgeHeader>0
}

sig PrivateCache extends Cache{}{
	#stored>0 implies	//for expiration date
		(some op:Maxage | op in HTTPResponse.headers.options) or 
		(some d:DateHeader, e:ExpiresHeader | d in HTTPResponse.headers and e in HTTPResponse.headers)

	#stored>0 and #(HTTPResponse -> Maxage)>0 implies	//for Maxage
		let A = HTTPResponse.headers.age, D = HTTPResponse.headers.date |
			let apparent = (restime.minus[D] > 0 implies restime.minus[D] else 0), corrected = A.plus[restime.minus[reqtime]] | 
				let initial = (apparent > corrected implies apparent else corrected) | 
					Maxage.time.minus[initial.plus[current.minus[restime]]] > 0

	#stored>0 and #(HTTPResponse -> ExpiresHeader)>0 and #(HTTPResponse -> Maxage)=0 implies	//for ExpiresHeader and DateHeader
		let A = HTTPResponse.headers.age, D = HTTPResponse.headers.date |
			let apparent = restime.minus[D] > 0 implies restime.minus[D] else 0, corrected = A.plus[restime.minus[reqtime]] | 
				let initial = apparent > corrected implies apparent else corrected | 
					all e:ExpiresHeader.expire, d:DateHeader.date | e.minus[d].minus[initial.plus[current.minus[restime]]] > 0
}

sig PublicCache extends Cache{}{
	#stored>0 implies no Private	//for Private
	
	#stored>0 implies	//for expiration date
		(some op:SMaxage | op in HTTPResponse.headers.options) or
		(some op:Maxage | op in HTTPResponse.headers.options) or
		(some d:DateHeader, e:ExpiresHeader | d in HTTPResponse.headers and e in HTTPResponse.headers)
	
	#stored>0 and #(HTTPResponse -> SMaxage)>0 implies	//for SMaxage
		let A = HTTPResponse.headers.age, D = HTTPResponse.headers.date |
			let apparent = restime.minus[D] > 0 implies restime.minus[D] else 0, corrected = A.plus[restime.minus[reqtime]] | 
				let initial = apparent > corrected implies apparent else corrected | 
					SMaxage.time.minus[initial.plus[current.minus[restime]]] > 0
	
	#stored>0 and #(HTTPResponse -> Maxage)>0 and #(HTTPResponse -> SMaxage)=0 implies	//for Maxage
		let A = HTTPResponse.headers.age, D = HTTPResponse.headers.date |
			let apparent = restime.minus[D] > 0 implies restime.minus[D] else 0, corrected = A.plus[restime.minus[reqtime]] | 
				let initial = apparent > corrected implies apparent else corrected | 
					Maxage.time.minus[initial.plus[current.minus[restime]]] > 0

	#stored>0 and #(HTTPResponse -> ExpiresHeader)>0 and  #(HTTPResponse -> SMaxage)=0 and  #(HTTPResponse -> Maxage)=0 implies	//for ExpiresHeader and DateHeader
		let A = HTTPResponse.headers.age, D = HTTPResponse.headers.date |
			let apparent = restime.minus[D] > 0 implies restime.minus[D] else 0, corrected = A.plus[restime.minus[reqtime]] | 
				let initial = apparent > corrected implies apparent else corrected | 
					all e:ExpiresHeader.expire, d:DateHeader.date | e.minus[d].minus[initial.plus[current.minus[restime]]] > 0
}

fact LimitHeader{
	all h:HTTPHeader | h in HTTPResponse.headers or h in HTTPRequest.headers
	all c:CacheOption | c in CacheControlHeader.options
	no res:HTTPResponse, req:HTTPRequest | res.headers = req.headers
	no resoption:ResponseCacheOption | resoption in HTTPRequest.headers.options
	no reqoption:RequestCacheOption | reqoption in HTTPResponse.headers.options
	lone h:CacheControlHeader | h in HTTPRequest.headers
	lone h:CacheControlHeader | h in HTTPResponse.headers
	one h:DateHeader | h in HTTPRequest.headers
	one h:DateHeader | h in HTTPResponse.headers
	lone h:ExpiresHeader | h in HTTPRequest.headers
	lone h:ExpiresHeader | h in HTTPResponse.headers
	lone h:AgeHeader | h in HTTPRequest.headers
	lone h:AgeHeader | h in HTTPResponse.headers
}

pred show(){	
	#PrivateCache.stored = 1
	#Maxage = 1
	#ExpiresHeader = 0
}

run show for 5