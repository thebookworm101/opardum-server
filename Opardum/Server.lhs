% Opardum
% A Collaborative Code Editor
% Written by Liam O'Connor-Davis with assistance from the
% rest of the Google Wave Team.
% Released under BSD3 License
%include lhs.include
\begin{document}
\title{Opardum: Server}
\maketitle
\ignore{

> {-# LANGUAGE TypeFamilies, EmptyDataDecls #-}
> {-# OPTIONS_GHC -fno-warn-orphans #-}

}
\section{Introduction}

In this module are contained singleton threads that manage initial client connections.

\section{Implementation}

> module Opardum.Server
>   ( module Opardum.Server.Types
>   , PortListener
>   ) where
>
> import Opardum.Websockets
> import Opardum.Processes
> import Opardum.DocumentManager
> import Opardum.OperationalTransforms
> import Opardum.Server.Types
> import Opardum.Storage
> import Opardum.Archiver
> 
> import Data.Char
> import qualified Data.Map as M
> import Control.Applicative ((<$>))
> import Network(Socket)
> import Control.Concurrent.Forkable

\subsection{Client Manager}

The client manager is a thread that performs initial data exchanges to determine which document
the client is requesting, and then if the document manager exists, connects the client to the
existing document manager, or if not, retrieves the document (if it exists) from storage and
starts a document manager for the client.

It uses a |Map| from @Data.Map@ to keep track of document manager channels.

Note that this is actually stored in the @ConcurrencyControl.Types@ module to prevent cyclic import errors.

When the client first connects, the first message sent by the client is interpreted to be the name
of the document they are requesting. A thread is spawned (|ask|) to monitor for this message and,
after the message is sent, the client is directed back to the clientManager to be added to a
document manager.

\begin{code}%
data instance ProcessCommands ClientManager = AddClient Client
                                            | AddClientToDoc Client String
                                            | RemoveDocument String
                                            deriving (Show)
data ClientManager
\end{code}

> instance Process ClientManager where
>   type ProcessInfo ClientManager = (Storage, Archiver)
>   type ProcessState ClientManager =  (M.Map String (ChanFor DocumentManager))
>   continue = do
>      (storage, archiver) <- getInfo
>      documents <- getState
>      message <- grabInbox
>      debug $ "clientManager recieved message: " ++ show message
>      inbox <- getInbox
>      case message of
>        RemoveDocument docName -> putState $ M.delete docName documents
>        AddClient client -> do forkIO $ io (ask client inbox); return ()
>        AddClientToDoc client docName -> do
>          case M.lookup docName documents of
>            Just chan -> NewClient client ~> chan
>            Nothing   -> do
>              snapshot <- strToSnapshot <$> (io $ getDocument storage docName)
>              debug $ "spawning document manager for document: " ++ docName
>              dm <- io $ spawnDocumentManager inbox docName snapshot storage archiver
>              NewClient client ~> dm
>              putState $ M.insert docName dm documents
>      continue
>      where
>        strToSnapshot :: String -> Op
>        strToSnapshot []  = []
>        strToSnapshot str = [Insert str]
>        ask client toCM = do
>          request <- readFrame client
>          case request of
>            Left _        -> disconnect client
>            Right docName -> if validName docName 
>                               then AddClientToDoc client docName ~> toCM
>                               else disconnect client
>        validName = all isAlphaNum

\subsection{Port Listener}

The port listener is a very dumb thread that simply listens on the specified TCP port for incoming
connections, forwarding to the client manager.

> data PortListener 
> instance Process PortListener where
>   type ProcessInfo PortListener = (Socket, ChanFor ClientManager, String, Int)
>   type ProcessState PortListener = ()
>   continue = do
>     (socket, toCM, location, port) <- getInfo
>     acceptWeb socket (\client -> do io $ sendFrame client "hello"; AddClient client ~> toCM)
>     continue
>   nullChannel _ = True

\end{document}
