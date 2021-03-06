% Opardum
% A Collaborative Code Editor 
% Written by Liam O'Connor-Davis with assistance from the
% rest of the Google Wave Team.
% Released under BSD3 License
%include lhs.include
\begin{document}
\title{Opardum: Concurrent Processes }
\maketitle

\ignore{

> {-# LANGUAGE GeneralizedNewtypeDeriving, FlexibleInstances, MultiParamTypeClasses, DeriveDataTypeable, TypeFamilies, ScopedTypeVariables #-}
> {-# OPTIONS_GHC -fno-warn-unused-do-bind #-}

}
\section{Introduction}

This utility module introduces a variety of convenience functions that are used for concurrency throughout Opardum.

At the heart of it is the |Process| class, which is the state transformer |stateT| over |IO|, designed to make it easier 
to write threads with thread-local state, and GHC type families, to generalize over message types.

> module Opardum.Processes
>   ( io
>   , debug
>   , (~>)
>   , grabMessage
>   , grabInbox
>   , ThreadState()
>   , Chan()
>   , Process(..)
>   , ProcessCommands
>   , runProcessWith
>   , runProcess
>   , runProcessStateless
>   , runProcessDumb
>   , switchTo
>   , createChannel
>   , getInbox
>   , getInfo
>   , getState
>   , putState
>   , ChanFor
>   ) where
>
> import qualified Control.Concurrent.Chan as C
> import Control.Concurrent.Forkable (ForkableMonad, forkIO)
> import Control.Monad.Trans
> import Control.Monad.State
> import Control.Monad.Reader
> import Control.Exception
> import Control.Applicative((<$>));
> import Data.Typeable

\section {Implementation}

First we define a convenience function because |liftIO| is annoying to type:

> io :: (MonadIO m) => IO a -> m a
> io = liftIO

As well as a version of |putStrLn| used for debugging in any |MonadIO|.

> debug :: (MonadIO m) => String -> m ()
> debug = io . putStrLn

\subsection {ThreadState Monad}

In order for thread-local storage, we shall define a |Reader| and |State| transformer over |IO|, which is our 
|ThreadStateM| type. The reader is used for read-only state such as channels to other processes and our
inbox channel, and the |State| transformer is used for mutating state. 

We will use GHC's @newtype@ @deriving@ feature to automatically make |ThreadStateM| an instance of |Monad|, 
|Functor|, |MonadState s|, |MonadReader r| and |MonadIO| automatically based on the definitions for the unboxed
action.

> newtype ThreadStateM r s v = ThreadState { unbox :: StateT s (ReaderT r IO) v }
>    deriving (Monad, Functor, MonadIO, MonadState s, MonadReader r, ForkableMonad)

Finally, seeing as the return type from the |ThreadStateM| monad does not usually matter, we define the
unit return to be |ThreadState|.

> type ThreadState r s = ThreadStateM r s ()

\subsection {Channels}

The next piece of the puzzle is some wrappers around the @Control.Concurrent.Chan@ library for use
in |ThreadState|. We also allow Channels to be \emph{nullable}, that is, they can be disabled when not needed in certain
plugins (for example archivers). Reading from a null channel results in a runtime exception, writing to one is a no-op.

> data Chan a = Chan (C.Chan a)
>             | NullChan

> data NullChannelException = NullChannelException
>      deriving (Show, Typeable)
>
> instance Exception NullChannelException

First, is the "send to" relation, |~>|, which is analogous to the |writeChan| function, lifted for any
|MonadIO|.

> (~>) :: MonadIO m => a -> Chan a -> m ()
> v ~> (Chan a) = io $ C.writeChan a v
> _ ~> (NullChan) = return ()

We also have an analog for the |readChan| function, |grabMessage|.

> grabMessage :: MonadIO m => Chan a -> m a
> grabMessage (Chan a) = io . C.readChan $ a
> grabMessage NullChan = throw NullChannelException

We also provide a way to |grabMessage| from a process inbox (see below)

> grabInbox :: ThreadStateM (Chan a,b) c a
> grabInbox = getInbox >>= grabMessage

And, predictably, an analog for the |newChan| function, which goes by the same name. These methods are not 
exported, however, as the only way to create a channel is based on the |Process| which owns it (see below).

> newChan :: (MonadIO m) => m (Chan a)
> newChan = Chan `liftM` (io C.newChan)

> newNullChan :: MonadIO m => m (Chan a)
> newNullChan = return NullChan

\subsection {Processes}

Seeing as message passing concurrency is exclusively used in Opardum, we define a \emph{Process} class that gives
a high-level generalization of all threaded computations, including the |ThreadState| computation itself, as well
as handling the creation of an ``inbox'' channel to that type, a message type, and channel nullability. In order 
to be able to generalize over types, we use the new GHC Extension, type families.

> type ChanFor p = Chan (ProcessCommands p)

> data family ProcessCommands p

> class Process p where
>   type ProcessInfo p
>   type ProcessState p 

The above three type families describe the type of the state of the process, the read-only information for the process,
such as channels, and also the data type that is used for messages sent into the process.

The |continue| method specifies the behavior of the thread. The state includes its inbox channel and whatever other
state is specified in the class.

>   continue :: ThreadState (ChanFor p, ProcessInfo p) (ProcessState p)

The |nullChannel| option specifies whether or not the channel created for this thread should be nulled, i.e, if the
thread does not read messages from the outside world, this will be |True|. This is used, for example, in automatic
archivers. The default value is false.

>   nullChannel :: p -> Bool
>   nullChannel = const False

We also provide simple means to retrieve either the state, channel, or read only info, rather than having to extract from 
the state tuple manually:

> getState :: ThreadStateM (a, b) c c
> getState = get

> putState :: c -> ThreadStateM (a, b) c ()
> putState = put

> getInbox :: ThreadStateM (a, b) c a
> getInbox = fst <$> ask

> getInfo :: ThreadStateM (a, b) c b
> getInfo = snd <$> ask

We introduce a runner for |Process|es, which is a wrapper around both |forkIO|, to spawn the thread, and |runStateT|,
to provide initial state.  It is worth noting that the exact process to invoke is determined entirely from the type
of the channel passed in, and hence the exact process to run is not specified upon use of this action.

> runProcessWith :: (MonadIO m, Process p)  => ChanFor p -> ProcessInfo p -> ProcessState p ->  m ()
> runProcessWith chan info state = 
>    let 
>      ThreadState v = continue 
>    in do
>      io $ forkIO $ flip runReaderT (chan, info) $ runStateT v state >> return ()
>      return ()

We also provide a means to create a channel destined for a particular process. For safety reasons (to prevent null
channels from ending up where they are not supposed to), this is the only way to create channels outside of this module.

A significant amount of glue is required to determine whether the channel should be null from the type.

> createChannel :: (MonadIO m, Process p) => m (ChanFor p)
> createChannel = do ret <- newNullChan
>                    if typesCheck ret then return ret else newChan
>        where  typesCheck :: (Process p) => ChanFor p -> Bool
>               typesCheck (_ :: ChanFor p) = nullChannel (undefined :: p)
>                                          

We provide two further ways to invoke a process. First, we provide |switchTo|, which allows the current thread to begin execution 
of the |Process|. This requires a (undefined) argument of the correct process type to determine the process to use, as the process
type cannot be determined from the channel as no channel is provided.

> switchTo :: (MonadIO m, Process p) => p -> ProcessInfo p -> ProcessState p -> m ()
> switchTo (_ :: p) info state = do c <- (createChannel :: MonadIO m => m (ChanFor p))
>                                   let v = unbox $ continue
>                                   io $ runReaderT (runStateT v state) (c, info)
>                                   return ()

Finally, we provide a convenience function to both create the channel for, and run a |Process| in another thread. The channel 
for the process is returned. Note that the process to run is determined entirely by context and need not be specified.

> runProcess :: (MonadIO m, Process p) => ProcessInfo p -> ProcessState p -> m (ChanFor p)
> runProcess info state = do c <- createChannel
>                            runProcessWith c info state 
>                            return c

And a helper for stateless threads:

> runProcessStateless :: (MonadIO m, Process p) => ProcessInfo p -> m (ChanFor p)
> runProcessStateless info = runProcess info (error "No state exists!")

And another for stateless, infoless threads:

> runProcessDumb :: (MonadIO m, Process p) => m (ChanFor p)
> runProcessDumb = runProcess (error "No info exists!") (error "No state exists!")

\end{document}
