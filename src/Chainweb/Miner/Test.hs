{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TemplateHaskell #-}

-- |
-- Module: Chainweb.Miner.Test
-- Copyright: Copyright © 2018 Kadena LLC.
-- License: MIT
-- Maintainer: Lars Kuhtz <lars@kadena.io>
-- Stability: experimental
--
-- TODO
--
module Chainweb.Miner.Test
( MinerConfig(..)
, defaultMinerConfig
, pMinerConfig
, miner
) where

import Configuration.Utils

import Control.Concurrent
import Control.Lens hiding ((.=))
import Control.Monad.STM

import Data.Reflection hiding (int)
import qualified Data.Text as T

import GHC.Generics (Generic)

import Numeric.Natural

import System.LogLevel
import qualified System.Random.MWC as MWC
import qualified System.Random.MWC.Distributions as MWC

-- internal modules

import Chainweb.BlockHeader
import Chainweb.Cut
import Chainweb.CutDB
import Chainweb.NodeId
import Chainweb.Utils
import Chainweb.WebChainDB

import Data.LogMessage

-- -------------------------------------------------------------------------- --
-- Configuration of Example

data MinerConfig = MinerConfig
    { _configNumberOfNodes :: !Natural
    , _configMeanBlockTimeSeconds :: !Natural
    }
    deriving (Show, Eq, Ord, Generic)

makeLenses ''MinerConfig

defaultMinerConfig :: MinerConfig
defaultMinerConfig = MinerConfig
    { _configNumberOfNodes = 10
    , _configMeanBlockTimeSeconds = 10
    }

instance ToJSON MinerConfig where
    toJSON o = object
        [ "numberOfNodes" .= _configNumberOfNodes o
        , "meanBlockTimeSeconds" .= _configMeanBlockTimeSeconds o
        ]

instance FromJSON (MinerConfig -> MinerConfig) where
    parseJSON = withObject "MinerConfig" $ \o -> id
        <$< configNumberOfNodes ..: "numberOfNodes" % o
        <*< configMeanBlockTimeSeconds ..: "meanBlockTimeSeconds" % o

pMinerConfig :: MParser MinerConfig
pMinerConfig = id
    <$< configNumberOfNodes .:: option auto
        % long "number-of-nodes"
        <> short 'n'
        <> help "number of nodes to run in the example"
    <*< configMeanBlockTimeSeconds .:: option auto
        % long "mean-block-time"
        <> short 'b'
        <> help "mean time for mining a block seconds"

-- -------------------------------------------------------------------------- --
-- Miner

miner
    :: LogFunction
    -> MinerConfig
    -> NodeId
    -> CutDb
    -> WebChainDb
    -> IO ()
miner logFun conf nid cutDb wcdb = do
    logg Info "Started Miner"
    gen <- MWC.createSystemRandom
    give wcdb $ go gen (1 :: Int)

  where
    logg :: LogLevel -> T.Text -> IO ()
    logg = logFun

    go :: Given WebChainDb => MWC.GenIO -> Int -> IO ()
    go gen i = do

        -- mine new block
        --
        d <- MWC.geometric1
            (1 / (int (_configNumberOfNodes conf) * int (_configMeanBlockTimeSeconds conf) * 1000000))
            gen
        threadDelay d

        -- get current longest cut
        --
        c <- _cut cutDb

        -- pick ChainId to mine on
        --
        -- chose randomly
        --

        -- create new (test) block header
        --
        let mine = do
                cid <- randomChainId c
                nonce <- MWC.uniform gen

                -- FIXME: use the node id
                testMine (Nonce nonce) cid c >>= \case
                    Nothing -> mine
                    Just x -> return x

        c' <- mine

        _ <- logg Debug $ "created new block" <> sshow i

        -- public cut into CutDb (add to queue)
        --
        atomically $ addCutHashes cutDb (cutToCutHashes Nothing c')

        -- continue
        --
        go gen (i + 1)

