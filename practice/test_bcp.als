open util/ordering[Time]

/***********************

Network Component

***********************/
abstract sig NetworkEndpoint{}
abstract sig HTTPConformist extends NetworkEndpoint{cache : lone Cache}
sig HTTPServer extends HTTPConformist{}
abstract sig HTTPClient extends HTTPConformist{
  owner:WebPrincipal // owner of the HTTPClient process
}
sig Browser extends HTTPClient {}
abstract sig HTTPIntermediary extends HTTPConformist{}
sig HTTPProxy extends HTTPIntermediary{}
sig HTTPGateway extends HTTPIntermediary{}

fact MoveOfIntermediary{
	all e:HTTPEvent |{
		e.from in HTTPIntermediary implies{	//e:中継者から送信されるイベント
			one original:HTTPEvent |{	//original:中継者に向けて送信されたイベント
				happensBefore[original, e]

				e.from = original.to
				e.uri = original.uri

				original in HTTPRequest implies {
					checkNotResponsed[original, e.current]
					e in HTTPRequest
				}

				original in HTTPResponse implies {
					e in HTTPResponse
					e.statusCode = original.statusCode
				}
			}
		}
	}
}

fact ReqAndResMaker{
	no req:HTTPRequest | req.from in HTTPServer
	no req:HTTPRequest | req.to in HTTPClient
	no res:HTTPResponse | res.from in HTTPClient
	no res:HTTPResponse | res.to in HTTPServer
}


/***********************

Event

***********************/
abstract sig Event {current : one Time}

abstract sig NetworkEvent extends Event {
	from: NetworkEndpoint,
	to: NetworkEndpoint
}

abstract sig HTTPEvent extends NetworkEvent {
	headers: set HTTPHeader,
	uri: one Uri,
	body :  set Token
}

sig HTTPRequest extends HTTPEvent {}
sig HTTPResponse extends HTTPEvent {statusCode: one Status}

//HTTPResponseの発生条件
fact happenResponse{
	all res:HTTPResponse | one req:HTTPRequest |{
		happensBefore[req, res]
		checkNotResponsed[req, res.current]
		res.uri = req.uri
		res.from = req.to
		res.to = req.from

		one t:HTTPTransaction | t.request = req and t.response = res
	}
}

//firstがsecondよりも前に発生する
pred happensBefore[first:Event,second:Event]{
	second.current in first.current.next.*next
}

//ある時点(t)でリクエストに応答されていない
pred checkNotResponsed[req: HTTPRequest, t: Time]{
	no res:HTTPResponse |{
		req.uri = res.uri

		{
			//req -> ... -> res -> ... -> tの順でベントが発生
			res.current in req.current.*next
			t in res.current.next.*next

			res.to = req.from
			res.from = req.to
		}or{
			some reuse:CacheReuse|{
				//req -> ... -> reuse -> ... -> tの順でベントが発生
				reuse.current in req.current.*next
				t in reuse.current.next.*next

				reuse.to = req.from
				reuse.target = res

				one p:NetworkEndpoint |{
					p.cache = reuse.happen
					(p = req.from) or (p = req.to)
				}
			}
		}
	}
}

//キャッシュの動作のイベントを定義
abstract sig CacheEvent extends Event {
	happen: one Cache,
	target: one HTTPResponse
}
sig CacheStore extends CacheEvent {}
sig CacheReuse extends CacheEvent {to: NetworkEndpoint}
sig CacheVerification extends CacheEvent {}

//CacheStoreの発生条件
fact happenCacheStore{
	all store:CacheStore | one res:HTTPResponse | {
		//レスポンスが以前にやりとりされている
		happensBefore[res, store]
		store.target = res
		store.happen = res.to.cache

		//レスポンスのヘッダ条件
		store.happen in PrivateCache implies {	//for PrivateCache
			(one op:Maxage | op in res.headers.options) or
			(one d:DateHeader, e:ExpiresHeader | d in res.headers and e in res.headers)
		}
		store.happen in PublicCache implies{	//for PublicCache
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
		happensBefore[req, reuse]
		checkNotResponsed[req, reuse.current]
		reuse.target.uri = req.uri
		req.to.cache = store.happen or req.from.cache = store.happen

		//過去の格納イベントに対する条件
		happensBefore[store, reuse]
		reuse.target = store.target

		//格納レスポンスの送信先
		reuse.to = req.from

		//HTTPTransactionに登録
		one t:HTTPTransaction | t.request = req and t.re_res = reuse
	}
}

//検証イベントの流れ
//CacheVerification -> HTTPRequest -> HTTPResponse -> CacheStore/HTTPResponse
fact happenCacheVerification{
	all veri:CacheVerification | {
		//応答するリクエストに対する条件
		one req:HTTPRequest |{
			happensBefore[req, veri]
			veri.target.uri = req.uri
			checkNotResponsed[req, veri.current]
		}

		//過去の格納イベントに対する条件
		one store:CacheStore | {
			happensBefore[store, veri]
			veri.target = store.target
			(one h:ETagHeader | h in veri.target.headers) or (one h:LastModifiedHeader | h in veri.target.headers)
		}

		//条件付リクエストの生成
		one req:HTTPRequest | {
			//リクエストの基本情報設定
			happensBefore[veri, req]
			one p:NetworkEndpoint | {
				p.cache = veri.happen
				req.from = p
			}
			req.to = veri.target.from
			req.uri = veri.target.uri

			//リクエストのヘッダ設定
			((one h:ETagHeader | h in veri.target.headers) implies (one h:IfNoneMatchHeader | h in req.headers)) or
			((one h:LastModifiedHeader | h in veri.target.headers) implies (one h:IfModifiedSinceHeader | h in req.headers))

			one h:HTTPHeader | {
				h in req.headers
				h in IfNoneMatchHeader + IfModifiedSinceHeader
			}

			//条件付リクエストへの応答
			one res:HTTPResponse | {
				happensBefore[req, res]
				res.from = req.to
				res.to = req.from
				(res.statusCode = c200) or (res.statusCode = c304)	//200:新しいレスポンスを使用, 304:レスポンスを再利用

				//検証結果に対する動作（新レスポンス or 再利用）
				(res.statusCode = c200) implies
					one res_result:HTTPResponse | {
						happensBefore[res, res_result]
						res_result.uri = res.uri
						res_result.from = res.from
						one req:HTTPRequest | {
							req.current.next = veri.current
							res_result.to = req.from
						}
					}

				(res.statusCode = c304) implies
					one reuse:CacheReuse | {
						happensBefore[res, reuse]
						reuse.target = veri.target
						reuse.to = req.from
					}
			}
		}
	}
}


/***********************

Headers

************************/
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
abstract sig RequestCacheOption extends CacheOption{}
abstract sig ResponseCacheOption extends CacheOption{}
//all
/*
sig Maxage,NoCache,NoStore,NoTransform extends CacheOption{}
sig MaxStale,MinStale,OnlyIfCached extends RequestCacheOption{}
sig MustRevalidate,Public,Private,ProxyRevalidate,SMaxage extends ResponseCacheOption{}
*/
//for simple model
sig Maxage,NoCache,NoStore extends CacheOption{}
sig OnlyIfCached extends RequestCacheOption{}
sig Private,SMaxage extends ResponseCacheOption{}

//どのリクエスト・レスポンスにも属さないヘッダは存在しない
//各ヘッダは適切なリクエスト・レスポンスに属する
//どのCacheControlヘッダにも属さないCacheOptiionは存在しない
fact noOrphanedHeaders {
	all h:HTTPRequestHeader|some req:HTTPRequest|h in req.headers
	all h:HTTPResponseHeader|some resp:HTTPResponse|h in resp.headers
	all h:HTTPGeneralHeader|some e:HTTPEvent | h in e.headers
	all h:HTTPEntityHeader|some e:HTTPEvent | h in e.headers
	all c:CacheOption | c in CacheControlHeader.options
	all c:RequestCacheOption | c in HTTPRequest.headers.options
	all c:ResponseCacheOption | c in HTTPResponse.headers.options
}

//CacheControlHeaderのオプションに関する制限
fact CCHeaderOption{
	//for "no-cache"
	all reuse:CacheReuse |{
		(some op:NoCache | op in reuse.target.headers.options) implies {
			one veri:CacheVerification | {
				happensBefore[veri,reuse]
				veri.target = reuse.target
				veri.happen = reuse.happen
			}
		}
	}

	//for "no-store"
	no store:CacheStore | some op:NoStore | op in store.target.headers.options

	//for only-if-cached
	all req:HTTPRequest | (some op:OnlyIfCached | op in req.headers.options) implies {
		some reuse:CacheReuse | {
			happensBefore[req, reuse]
			reuse.target.uri = req.uri
			reuse.to = req.from
		}
	}

	//for "private"
	no op:Private | some store:CacheStore | {
		store.happen in PublicCache
		op in store.target.headers.options
	}
}


/****************************

Cache

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
	all p:NetworkEndpoint | lone c:Cache | c in p.cache
}

fact PublicAndPrivate{
	all pri:PrivateCache | pri in HTTPClient.cache
	all pub:PublicCache | (pub in HTTPServer.cache) or (pub in HTTPIntermediary.cache)
}


/***********************

DNS

************************/
fact DNSIsDisjointAmongstPrincipals {
	all disj p1,p2 : Principal | no (p1.servers & p2.servers)
}


/***********************

Token

************************/
sig Time {}

fact Traces{
	all t:Time | one e:Event | t = e.current
}

abstract sig Token {}

fact noOrphanedToken{
	all t:Token | some e:HTTPEvent | t in e.body
}

sig Uri{}

//使用されないURIは存在しない
fact noOrphanedUri{
	all u:Uri | some e:HTTPEvent | u = e.uri
}

//レスポンスの状態コード
abstract sig Status  {}
abstract sig RedirectionStatus extends Status {}
lone sig c200 extends Status{}
lone sig c304 extends RedirectionStatus {}
/*
lone sig c200,c401 extends Status{}
lone sig c301,c302,c303,c304,c305,c306,c307 extends RedirectionStatus {}
*/


/***********************

Network Character

***********************/
abstract sig Principal {
	servers : set NetworkEndpoint,
}

abstract sig PassivePrincipal extends Principal{}{
	servers in HTTPConformist
}

abstract sig WebPrincipal extends PassivePrincipal {
 	httpClients : set HTTPClient
} { httpClients.owner = this }

sig ACTIVEATTACKER extends Principal{}	//GadgetAttacker
sig PASSIVEATTACKER extends PassivePrincipal{}	//WebAttacker
sig WEBATTACKER extends WebPrincipal{}	//NetworkAttacker

sig Alice extends WebPrincipal {}
sig Mallory extends WEBATTACKER {}


/***********************

HTTPTransaction

************************/
sig HTTPTransaction {
	request : one HTTPRequest,
	response : lone HTTPResponse,
	re_res : lone CacheReuse,
	//cert : lone Certificate,
	//cause : lone HTTPTransaction + RequestAPI
}{
	some response implies {
		//response can come from anyone but HTTP needs to say it is from correct person and hosts are the same, so schema is same
		happensBefore[request,response]
	}

	some re_res implies {
		happensBefore[request, re_res]
	}
}

fact limitHTTPTransaction{
	all req:HTTPRequest | lone t:HTTPTransaction | t.request = req
	no t:HTTPTransaction |{
		some t.response and some t.re_res
	}
}


/****************************

Test Code

****************************/
run test_reuse{
	#HTTPClient = 1
	#HTTPServer = 1
	#HTTPIntermediary = 0
	#PrivateCache = 1
	#PublicCache = 0

	#CacheReuse = 1

	#IfModifiedSinceHeader = 0
	#LastModifiedHeader = 0
	#IfNoneMatchHeader = 0
	#ETagHeader = 0
	#DateHeader = 0
	#ExpiresHeader = 0
	//#AgeHeader = 0
	//#CacheControlHeader = 0

	no h:HTTPHeader |{
		h in HTTPRequest.headers
	}
} for 5

run test_intermediary{
	#HTTPClient = 1
	#HTTPServer = 1
	#HTTPIntermediary = 1
	#Cache = 0

	#HTTPRequest = 2
	#HTTPResponse = 2

	#IfModifiedSinceHeader = 0
	#LastModifiedHeader = 0
	#IfNoneMatchHeader = 0
	#ETagHeader = 0
	#DateHeader = 0
	#ExpiresHeader = 0
	#AgeHeader = 0
	//#CacheControlHeader = 0

	no h:HTTPHeader |{
		h in HTTPRequest.headers
	}

	all req:HTTPRequest | {
		req.from in HTTPClient implies req.to in HTTPIntermediary
		req.from in HTTPIntermediary implies req.to in HTTPServer
	}

	all res:HTTPResponse | {
		res.from in HTTPServer implies res.to in HTTPIntermediary
		res.from in HTTPIntermediary implies res.to in HTTPClient
	}
} for 4

run cachemine{
	#HTTPClient = 1
	#HTTPServer = 1
	#HTTPIntermediary = 1
	#Cache = 1
	#PrivateCache = 1

	#HTTPRequest = 2
	#HTTPResponse = 2
	#CacheStore = 1

	#IfModifiedSinceHeader = 0
	#LastModifiedHeader = 0
	#IfNoneMatchHeader = 0
	#ETagHeader = 0
	#DateHeader = 0
	#ExpiresHeader = 0
	//#AgeHeader = 2
	//#CacheControlHeader = 2

	#Uri = 1

	no h:HTTPHeader |{
		h in HTTPRequest.headers
	}

	all req:HTTPRequest | {
		req.from in HTTPClient implies req.to in HTTPIntermediary
		req.from in HTTPIntermediary implies req.to in HTTPServer
	}

	all res:HTTPResponse | {
		res.from in HTTPServer implies res.to in HTTPIntermediary
		res.from in HTTPIntermediary implies res.to in HTTPClient
	}
} for 5

run bcp{
	#HTTPClient = 1
	#HTTPServer = 1
	#HTTPIntermediary = 1
	#PrivateCache = 1
	#PublicCache = 0

	#HTTPRequest = 3
	#HTTPResponse = 2
	#CacheStore = 1
	#CacheReuse = 1

	#IfModifiedSinceHeader = 0
	#LastModifiedHeader = 0
	#IfNoneMatchHeader = 0
	#ETagHeader = 0
	#DateHeader = 0
	#ExpiresHeader = 0
	//#AgeHeader = 0
	//#CacheControlHeader = 0

	all req:HTTPRequest | {
		req.from in HTTPClient implies req.to in HTTPIntermediary
		req.from in HTTPIntermediary implies req.to in HTTPServer

		#(req.body) = 0
	}

	all res:HTTPResponse | {
		res.from in HTTPServer implies res.to in HTTPIntermediary
		res.from in HTTPIntermediary implies res.to in HTTPClient

		#(res.body) = 1
		all disj res1, res2:HTTPResponse | no t:Token | t in res1.body and t in res2.body
	}
} for 7

run test_alice{
	//one HTTPClient
	//one HTTPServer
	//no HTTPIntermediary
	//no Cache

	//one HTTPRequest
	//one HTTPResponse

	//no HTTPHeader

	#Principal = 2
	#Alice = 1
	#WEBATTACKER = 1
	//no point:NetworkEndpoint | point in Mallory.servers and point in Browser
} for 2
