import sugar

type
  # TODO: define error type
  Error* = ref object
    msg: string

  Observer*[T] = ref object
    onNext*: (T)->void
    onError*: (Error)->void
    onCompleted*: ()->void
  IObservable*[T] = ref object
    onSubscribe*: Observer[T]->IDisposable
    hasAnyObservers*: ()->bool
    removeObserver*: (Observer[T])->void
  IDisposable* = ref object
    dispose*: ()->void
  Subscription[T] = ref object
    iDisposable: IDisposable
    iObservable: IObservable[T]
    observer: Observer[T]
    isDisposed: bool

proc doNothing[T](v: T): void = discard
proc doNothing(): void = discard

proc newError*(msg: string): Error = Error(msg: msg)
proc `$`*(e: Error): string = e.msg

# Subscription ==========================================================================
proc newSubscription*[T](iObservable: IObservable[T]; observer: Observer[T]):
                                                                  IDisposable =
  let subscription = Subscription[T](
    iObservable: iObservable,
    observer: observer,
  )
  subscription.iDisposable = IDisposable(dispose: proc(): void =
    if subscription.isDisposed or not subscription.iObservable.hasAnyObservers():
      return
    subscription.iObservable.removeObserver(subscription.observer)
    subscription.isDisposed = true
  )
  return subscription.iDisposable

# Observer ============================================================================
proc newObserver*[T](onNext: (T)->void;
                     onError: (Error)->void = doNothing[Error];
                     onCompleted: ()->void = doNothing): Observer[T] =
  Observer[T](onNext: onNext, onError: onError, onCompleted: onCompleted)

# Observable ==========================================================================
proc subscribe*[T](self: IObservable[T]; observer: Observer[T]): IDisposable =
  self.onSubscribe(observer)
template subscribe*[T](self: IObservable[T];
    onNext: (T)->void;
    onError: (Error)->void = doNothing[Error];
    onCompleted: ()->void = doNothing): IDisposable =
  ## The sugar to:
  ##
  ## .. code-block:: Nim
  ##    discard someObservable
  ##      .subscribe(newObserver(
  ##        (v: T) => onNext(v),
  ##        (e: Error) => onError(e),
  ##        () => onCompleted()
  ##      ))
  ##
  ## It enable us to write:
  ##
  ## .. code-block:: Nim
  ##    discard someObservable
  ##      .subscribe(
  ##        (v: T) => onNext(v),
  ##        (e: Error) => onError(e),
  ##        () => onCompleted()
  ##      )
  self.subscribe(newObserver(onNext, onError, onCompleted))
