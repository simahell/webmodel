open util/ordering[Time]

abstract sig Principal {
	servers : set NetworkEndpoint,
}

fact DNSIsDisjointAmongstPrincipals {
	all disj p1,p2 : Principal | no (p1.servers & p2.servers)
}

sig Time {}

//イベントが直後に発生する制限解除
/*
pred happensBeforeOrdering[first:Event,second:Event]{
	second.current in first.current.*next
}
*/

fact Traces{
	all t:Time | one e:Event | t = e.current
}

sig NetworkEndpoint{cache : lone Cache}

//----- イベント記述 -----
abstract sig Event {
	current : one Time
}

abstract sig NetworkEvent extends Event {
	from: NetworkEndpoint,
	to: NetworkEndpoint
}

abstract sig HTTPEvent extends NetworkEvent {
	headers: set HTTPHeader,
	uri : one Uri
}
sig HTTPRequest extends HTTPEvent {}
sig HTTPResponse extends HTTPEvent {}

fact happenResponse{
	all res:HTTPResponse | one req:HTTPRequest |{
		res.current = req.current.next
		res.uri = req.uri
	}
}

abstract sig CacheEvent extends Event {
	happen: one Cache,
	target: one HTTPResponse
}
sig CacheStore extends CacheEvent {}
sig CacheReuse extends CacheEvent {}
sig CacheVerification extends CacheEvent {}

//CacheStoreの発生条件
fact happenCacheStore{
	all e:CacheStore | one res:HTTPResponse | {
		//レスポンスが直前にやりとりされている
		e.current = res.current.next
		e.target = res
		e.happen = res.to.cache

		//レスポンスのヘッダ条件
		e.happen in PrivateCache implies {	//for PrivateCache
			(one op:Maxage | op in res.headers.options) or
			(one d:DateHeader, e:ExpiresHeader | d in res.headers and e in res.headers)
		}else{	//for PublicCache
			(one op:Maxage | op in res.headers.options) or
			(one op:SMaxage | op in res.headers.options) or
			(one d:DateHeader, e:ExpiresHeader | d in res.headers and e in res.headers)

			no op:Private | op in res.headers.options
		}
		one h:AgeHeader | h in res.headers
	}
}

//CacheReuseの発生条件
fact happenCacheReuse{
	all reuse:CacheReuse | one store:CacheStore, req:HTTPRequest |{
		//応答するリクエストに対する条件
		reuse.current = req.current.next
		reuse.target.uri = req.uri

		//過去の格納イベントに対する条件
		store.current in Time - reuse.current.*next
		reuse.target = store.target
	}
}

fact happenCacheVerification{
	all veri:CacheVerification | some store:CacheStore, req:HTTPRequest |{
		//応答するリクエストに対する条件
		veri.current = req.current.next
		veri.target.uri = req.uri

		//過去の格納イベントに対する条件
		store.current in Time - veri.current.*next
		veri.target = store.target
	}

	//条件付レスポンスの生成

	//条件付レスポンスへの応答

	//検証結果に対する動作（再利用 or 新レスポンス）

}

//----- トークン記述 -----
sig Uri{}

//使用されないURIは存在しない
fact noOrphanedUri{
	all u:Uri | some e:HTTPEvent | u = e.uri
}

//----- HTTPヘッダ記述 -----
abstract sig HTTPHeader {}
abstract sig HTTPResponseHeader extends HTTPHeader{}
abstract sig HTTPRequestHeader extends HTTPHeader{}
abstract sig HTTPGeneralHeader extends HTTPHeader{}
abstract sig HTTPEntityHeader extends HTTPHeader{}

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

//どのリクエスト・レスポンスにも属さないヘッダは存在しない
//各ヘッダは適切なリクエスト・レスポンスに属する
//どのCacheControlヘッダにも属さないCacheOptiionは存在しない
fact noOrphanedHeaders {
	all h:HTTPRequestHeader|one req:HTTPRequest|h in req.headers
	all h:HTTPResponseHeader|one resp:HTTPResponse|h in resp.headers
	all h:HTTPGeneralHeader|one e:HTTPEvent | h in e.headers
	all h:HTTPEntityHeader|one e:HTTPEvent | h in e.headers
	all c:CacheOption | c in CacheControlHeader.options
}

/****************************

Cache Definitions

****************************/

abstract sig Cache{}
sig PrivateCache extends Cache{}
sig PublicCache extends Cache{}

//どの端末にも属さないキャッシュは存在しない
fact noOrphanedCaches {
	all c:Cache |
		one e:NetworkEndpoint | c = e.cache
}

//同じ端末に2つ以上のキャッシュは存在しない
fact noMultipleCaches {
	no disj e1, e2:NetworkEndpoint | e1.cache = e2.cache
}

run {
	#PublicCache = 1
	#CacheStore = 1
	//#CacheReuse = 1

	#IfModifiedSinceHeader = 0
	#IfNoneMatchHeader = 0
	#ETagHeader = 0
	#LastModifiedHeader = 0
	#AgeHeader = 0
	#DateHeader = 0
	#ExpiresHeader = 0
} for 3
