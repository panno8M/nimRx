# Cording Convention
#
# Since the chain does not continue from the following functions, 
# the parentheses should be omitted and the description should be procedural:
# * Observer[T].onNext val
# * Observer[T].onError err
# * Observer[T].onComplete()
# * IObservable[T].subscribe observer
#
# IObservable[T].subscribe(
#   (v: T) => doSomething(),
#   (e: Error) => (doSomething(); doOtherThing()),
#   (proc(v: T) =
#     doSomething()
#     doSomething()
#     doSomething()
#   ),
# )

{.experimental: "strictFuncs".}

import sugar
import sequtils

# rx
import core
import subjects



# SECTION Utilities

template construct_whenSubscribed*[T](
  mkObservable: untyped): untyped =
  Observable[T](onSubscribe: proc(ober: Observer[T]): Disposable =
    (() => mkObservable)().subscribe ober
  )

template combineDisposables(disps: varargs[Disposable]): Disposable =
  Disposable(dispose: () => @disps.apply((it: Disposable) => it.dispose()))

# Indicate whether operator perform a special behavior.
template onNext_default[T](observer: Observer[T]): (v: T)->void =
  (v: T) => observer.onNext(v)
template onError_default[T](observer: Observer[T]): (e: ref Exception)->void =
  (e: ref Exception) => observer.onError(e)
template onComplete_default[T](observer: Observer[T]): ()->void =
  () => observer.onComplete()

# !SECTION

# SECTION Creating

func just*[T](v: T): Observable[T] =
  ## "[Just](http://reactivex.io/documentation/operators/just.html)" from ReactiveX
  runnableExamples:
    import rx
    import sugar

    var
      res: int
      isCompleted: bool

    discard just(10)
      .subscribe(
        onNext = (x: int) => (res = x),
        onComplete = () => (isCompleted = true))

    assert res == 10
    assert isCompleted

  construct_whenSubscribed[T]:
    let retObservable = new Observable[T]
    retObservable.onSubscribe = proc(observer: Observer[T]): Disposable =
      observer.onNext v
      observer.onComplete()
      newSubscription(retObservable, observer)
    return retObservable


func range*[T: Ordinal](start: T; count: Natural): Observable[T] =
  ## "[Range](http://reactivex.io/documentation/operators/range.html)" from ReactiveX
  runnableExamples:
    import rx
    import sugar

    var
      res: int
      isCompleted: bool

    discard range(1, 4)
      .subscribe(
        onNext = (x: int) => (res += x),
        onComplete = () => (isCompleted = true),
      )

    assert res == 10
    assert isCompleted

  construct_whenSubscribed[T]:
    let retObservable = new Observable[T]
    retObservable.onSubscribe = proc(observer: Observer[T]): Disposable =
      for i in 0..<count:
        observer.onNext start.succ(i)
      observer.onComplete()
      newSubscription(retObservable, observer)
    return retObservable

func repeat*[T](upstream: Observable[T]; times: Natural = 0): Observable[T] =
  ## | "[Repeat](http://reactivex.io/documentation/operators/repeat.html)" from ReactiveX
  ## | if "times" == 0: It will repeat stream infinitely.
  ## | if "times" >= 1: It will repeat stream "times" times.
  # TODO: To write runnable examples, need to implement take** operators.
  # I thought about separating infinite and finite into different functions,
  # but in any case, the finite version changes the process depending on
  # whether times is zero or not. Then I thought it would be cleaner to combine them.
  construct_whenSubscribed[T]:
    var stat: Natural = times
    proc mkRepeatObserver(observer: Observer[T]): Observer[T] =
      return newObserver[T](
        observer.onNext_default,
        observer.onError_default,
        proc() =
        case stat:
          # Process: infinity
          of 0:
            discard upstream.subscribe observer.mkRepeatObserver()
          # Process: finity
          of 1: # End point.
            observer.onComplete()
          else:
            dec stat
            discard upstream.subscribe observer.mkRepeatObserver()
      )
    newObservable[T] proc(observer: Observer[T]): Disposable =
      return upstream.subscribe observer.mkRepeatObserver()

# !SECTION

# SECTION Transforming

func buffer*[T](upstream: Observable[T]; timeSpan: Natural; skip: Natural = 0):
                                                                Observable[seq[T]] =
  ## "[Buffer](http://reactivex.io/documentation/operators/buffer.html)" from ReactiveX
  runnableExamples:
    import rx
    import sugar

    var res = newSeq[int]()

    discard range(0, 5)
      .buffer(2, 1)
      .filter(x => x.len == 2) # If "buffer" reciexed onComplete exent, it will flush stored xalues 
                              # whether it has enough length or not.
      .map(x => x[0]*x[1])
      .subscribe((x: int) => (res.add x))

    doAssert res == @[0*1, 1*2, 2*3, 3*4]
  runnableExamples:
    import rx
    import sugar

    var res = newSeq[int]()

    discard range(0, 6)
      .buffer(3)
      .filter(x => x.len == 3)
      .map(x => x[0] + x[1] + x[2])
      .subscribe((x: int) => (res.add x))

    doAssert res == @[3, 12]

  let skip = if skip == 0: timeSpan else: skip
  type S = seq[T]
  construct_whenSubscribed[S]:
    var cache = newSeq[T]()
    newObservable[S] proc(observer: Observer[S]): Disposable =
      upstream.subscribe(
        (proc(v: T) =
          cache.add v
          if cache.len == timeSpan:
            observer.onNext cache
            cache = cache[skip..cache.high]
        ),
        observer.onError_default,
        (proc() =
          if cache.len != 0: observer.onNext cache
          observer.onComplete()
        ),
      )

func map*[T, S](upstream: Observable[T]; op: (T)->S): Observable[S] =
  ## "[Map](http://reactivex.io/documentation/operators/map.html)" from ReactiveX
  runnableExamples:
    import rx
    import sugar

    var res = newSeq[int]()
    let sbj = newSubject[int]()
    discard sbj
      .map(x => x*10)
      .subscribe((x: int) => (res.add x))
    sbj.onNext 1
    sbj.onNext 2
    sbj.onNext 3

    doAssert res == @[10, 20, 30]

  construct_whenSubscribed[S]:
    newObservable[S] proc(observer: Observer[S]): Disposable =
      upstream.subscribe(
        (v: T) => observer.onNext op(v),
        observer.onError_default,
        observer.onComplete_default,
      )

#!SECTION

# SECTION Filtering

func filter*[T](upstream: Observable[T]; op: (T)->bool): Observable[T] =
  ## "[Filter](http://reactivex.io/documentation/operators/filter.html)" from ReactiveX
  runnableExamples:
    import rx
    import sugar

    var res = newSeq[int]()
    let sbj = newSubject[int]()
    discard sbj
      .filter(x => x > 10)
      .subscribe((x: int) => (res.add x))
    sbj.onNext 2
    sbj.onNext 30
    sbj.onNext 22
    sbj.onNext 5
    sbj.onNext 60
    sbj.onNext 1

    doAssert res == @[30, 22, 60]

  construct_whenSubscribed[T]:
    newObservable[T] proc(observer: Observer[T]): Disposable =
      upstream.subscribe(
        (v: T) => (if op(v): observer.onNext v),
        observer.onError_default,
        observer.onComplete_default,
      )

# !SECTION

# SECTION Combining

func zip*[Tl, Tr](tl: Observable[Tl]; tr: Observable[Tr]):
                                                  Observable[(Tl, Tr)] =
  ## "[Zip](http://reactivex.io/documentation/operators/zip.html)" from ReactiveX
  runnableExamples:
    import rx
    import sugar, strformat

    var res = newSeq[string]()
    let sbj1 = newSubject[int]()
    let sbj2 = newSubject[char]()
    discard sbj1.zip( <>sbj2 )
      .subscribe((v: (int, char)) => res.add &"{v[0]}{v[1]}")
    sbj1.onNext 1
    sbj2.onNext 'A'
    sbj1.onNext 2
    sbj2.onNext 'B'
    sbj2.onNext 'C'
    sbj2.onNext 'D'
    sbj1.onNext 3
    sbj1.onNext 4
    sbj1.onNext 5

    doAssert res == @["1A", "2B", "3C", "4D"]

  type S = (Tl, Tr)
  construct_whenSubscribed[S]:
    var cache: tuple[l: seq[Tl]; r: seq[Tr]] = (newSeq[Tl](), newSeq[Tr]())
    proc tryOnNext(observer: Observer[S]) =
      if cache.l.len != 0 and cache.r.len != 0:
        observer.onNext (cache.l[0], cache.r[0])
        cache.l = cache.l[1..cache.l.high]
        cache.r = cache.r[1..cache.r.high]
    newObservable[S] proc(observer: Observer[S]): Disposable =
      let disps = @[
        tl.subscribe(
          (v: Tl) => (cache.l.add v; observer.tryOnNext()),
          observer.onError_default,
        ),
        tr.subscribe(
          (v: Tr) => (cache.r.add v; observer.tryOnNext()),
          observer.onError_default,
        ),
      ]
      disps.combineDisposables()

proc zip*[T](upstream: Observable[T]; targets: varargs[Observable[T]]):
                                                              Observable[seq[T]] =
  ## "[Zip](http://reactivex.io/documentation/operators/zip.html)" from ReactiveX
  runnableExamples:
    import rx
    import sugar, strformat

    var res = newSeq[string]()
    let
      sbj1 = newSubject[char]()
      sbj2 = newSubject[char]()
      sbj3 = newSubject[char]()
    discard sbj1.zip( <>sbj2, <>sbj3 )
      .subscribe((x: seq[char]) => res.add &"{x[0]}{x[1]}{x[2]}")
    sbj1.onNext '1'
    sbj2.onNext 'a'
    sbj1.onNext '2'
    sbj3.onNext 'A'
    sbj2.onNext 'b'
    sbj1.onNext '3'
    sbj3.onNext 'B'
    sbj3.onNext 'C'

    doAssert res == @["1aA", "2bB"]

  let targets = concat(@[upstream], @targets)
  type S = seq[T]
  construct_whenSubscribed[S]:
    var cache = newSeqWith(targets.len, newSeq[T]())
    # Is this statement put directly in the for statement on onSubscribe,
    # the values from all obles will go into cache[seq.high].
    proc trySubscribe(target: tuple[oble: Observable[T]; i: int];
        observer: Observer[S]): Disposable =
      target.oble.subscribe(
        (proc(v: T) =
          cache[target.i].add(v)
          if cache.filterIt(it.len == 0).len == 0:
            observer.onNext cache.mapIt(it[0])
            cache = cache.mapIt(it[1..it.high])
        ),
        observer.onError_default,
      )
    newObservable[S] proc(observer: Observer[S]): Disposable =
      var disps = newSeq[Disposable](targets.len)
      for i, target in targets:
        disps[i] = (target, i).trySubscribe(observer)
      disps.combineDisposables()

# !SECTION

# SECTION Error handling

func retry*[T](upstream: Observable[T]): Observable[T] =
  ## "[Retry](http://reactivex.io/documentation/operators/retry.html)" from ReactiveX
  # TODO: To write runnable examples, needs to implement replaySubject.
  # NOTE: without this assignment, the upstream variable in retryConnection called later is not found.
  # ...I do not know why. :-(
  func mkRetryObserver(observer: Observer[T]): Observer[T] =
    newObserver[T](
      observer.onNext_default,
      (e: ref Exception) => (discard upstream.subscribe observer.mkRetryObserver()),
      observer.onComplete_default,
    )
  construct_whenSubscribed[T]:
    newObservable[T] proc(observer: Observer[T]): Disposable =
      upstream.subscribe observer.mkRetryObserver()

# !SECTION

# SECTION Mathematical and Aggregate
proc concat*[T](upstream: Observable[T]; targets: varargs[Observable[T]]):
                                                                Observable[T] =
  ## "[Concat](http://reactivex.io/documentation/operators/concat.html)" from ReactiveX
  runnableExamples:
    import rx
    import sugar

    var res = newSeq[int]()
    let
      sbj1 = newSubject[int]()
      sbj2 = newSubject[int]()
    discard sbj1.concat( <>sbj2 )
      .subscribe(
        onNext = (x: int) => res.add x,
        onComplete = () => res.add 0)
    sbj1.onNext 1
    sbj2.onNext 2
    sbj1.onNext 1
    sbj1.onComplete()
    sbj2.onNext 2
    sbj2.onComplete()

    doAssert res == @[1, 1, 2, 0]

  let targets = @targets
  construct_whenSubscribed[T]:
    var
      i_target = 0
      retDisp: Disposable
    proc nextTarget(): Observable[T] =
      result = targets[i_target]
      inc i_target
    proc mkConcatObserver(observer: Observer[T]): Observer[T] =
      newObserver[T](
        observer.onNext_default,
        observer.onError_default,
        (proc() =
          if i_target < targets.len:
            retDisp = nextTarget().subscribe observer.mkConcatObserver()
          else:
            observer.onComplete()
        ),
      )
    newObservable[T] proc(observer: Observer[T]): Disposable =
      retDisp = upstream.subscribe observer.mkConcatObserver()
      Disposable(dispose: () => retDisp.dispose())

# !SECTION

# SECTION Cold -> Hot converter

type ConnectableObservable[T] = ref object
  subject: Subject[T]
  upstream: Observable[T]
  disposable_isItAlreadyConnected: Disposable
converter toObservable*[T](self: ConnectableObservable[T]): Observable[T] = self.subject
template `<>`*[T](self: ConnectableObservable[T]): Observable[T] = self.toObservable
func publish*[T](upstream: Observable[T]): ConnectableObservable[T] =
  runnableExamples:
    import rx
    import rx/unitUtils
    import sugar

    var cntCalled: int
    let
      sbj = newSubject[Unit]()
      published = sbj
        .doThat((_: Unit) => (inc cntCalled))
        .publish()

    sbj.onNext()
    assert cntCalled == 0

    discard published
      .subscribeBlock:
        discard

    sbj.onNext()
    assert cntCalled == 0

    let disconnectable = published.connect()

    sbj.onNext()
    assert cntCalled == 1

    discard published
      .subscribeBlock:
        discard

    sbj.onNext()
    assert cntCalled == 2

    disconnectable.dispose()

    sbj.onNext()
    assert cntCalled == 2

  ConnectableObservable[T](
    subject: newSubject[T](),
    upstream: upstream,
  )

proc connect*[T](self: ConnectableObservable[T]): Disposable =
  ## See `publish proc<#publish,IObservable[T]>`_ for examples.
  # Do nothing when already connected between "publish subject" to its upstream
  if self.disposable_isItAlreadyConnected == nil:
    var dispSbsc = self.upstream.subscribe(
      (v: T) => self.subject.onNext v,
      (e: ref Exception) => self.subject.onError e,
      () => self.subject.onComplete(),
    )
    self.disposable_isItAlreadyConnected = Disposable(dispose: proc() =
      dispSbsc.dispose()
      self.disposable_isItAlreadyConnected = nil
    )
  return self.disposable_isItAlreadyConnected

func refCount*[T](upstream: ConnectableObservable[T]): Observable[T] =
  ## NOTE: There is something wrong with this behavior.
  ## Be careful when use it.
  var
    cntSubscribed = 0
    dispConnect: Disposable
  newObservable[T] proc(observer: Observer[T]): Disposable =
    let dispSubscribe = upstream.subscribe observer
    inc cntSubscribed
    if cntSubscribed == 1:
      dispConnect = upstream.connect()
    return Disposable(dispose: proc() =
      dec cntSubscribed
      if cntSubscribed == 0:
        dispConnect.dispose()
      dispSubscribe.dispose()
    )

func share*[T](upstream: Observable[T]): Observable[T] =
  upstream.publish().refCount()

# !SECTION

# SECTION Value dump

func doThat*[T](upstream: Observable[T]; op: (T)->void): Observable[T] =
  construct_whenSubscribed[T]:
    newObservable[T] proc(observer: Observer[T]): Disposable =
      upstream.subscribe(
        (v: T) => (op(v); observer.onNext v),
        observer.onError_default,
        observer.onComplete_default,
      )

func dump*[T](upstream: Observable[T]): Observable[T] =
  template log(action: untyped): untyped = debugEcho "[DUMP] ", action
  construct_whenSubscribed[T]:
    newObservable[T] proc(observer: Observer[T]): Disposable =
      upstream.subscribe(
        (v: T) => (log v; observer.onNext v),
        (e: ref Exception) => (log e; observer.onError e),
        () => (log "complete!"; observer.onComplete()),
      )

# !SECTION
