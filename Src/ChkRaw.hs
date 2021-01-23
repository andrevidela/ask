{-# LANGUAGE TupleSections, LambdaCase, PatternSynonyms #-}

module Ask.Src.ChkRaw where

import Data.List
import Data.Char
import Control.Arrow ((***))
import Data.Bifoldable
import Control.Applicative

import Debug.Trace

import Ask.Src.Thin
import Ask.Src.Bwd
import Ask.Src.OddEven
import Ask.Src.Lexing
import Ask.Src.RawAsk
import Ask.Src.Tm
import Ask.Src.Glueing
import Ask.Src.Context
import Ask.Src.Typing
import Ask.Src.Proving
import Ask.Src.Printing
import Ask.Src.HardwiredRules

track = const id

type Anno =
  ( Status
  , Bool    -- is it proven?
  )

data Status
  = Junk Gripe
  | Keep
  | Need
  deriving Show

passive :: Prove () Appl -> Prove Anno TmR
passive (Prove g m () ps src) =
  Prove (Your g) (fmap Your m) (Keep, False) (fmap subPassive ps) src
  
subPassive :: SubProve () Appl -> SubProve Anno TmR
subPassive ((srg, gs) ::- p) = (srg, map (fmap Your) gs) ::- passive p
subPassive (SubPGuff ls) = SubPGuff ls

surplus :: Prove () Appl -> Prove Anno TmR
surplus (Prove g m () ps src) =
  Prove (Your g) (fmap Your m) (Junk Surplus, True) (fmap subPassive ps) src
  
subSurplus :: SubProve () Appl -> SubProve Anno TmR
subSurplus ((srg, gs) ::- p) = (srg, map (fmap Your) gs) ::- surplus p
subSurplus (SubPGuff ls) = SubPGuff ls

-- this type is highly provisional
chkProof
  :: TmR         -- the goal
  -> Method Appl -- the method
  -> Bloc (SubProve () Appl)  -- the subproofs
  -> ([LexL], [LexL])  -- source tokens (head, body)
  -> AM (Prove Anno TmR)  -- the reconstructed proof

chkProof g m ps src = cope go junk return where
  junk gr = return $ Prove g (fmap Your m) (Junk gr, True)
    (fmap subPassive ps) src
  go = case my g of
    Just gt -> do
      m <- case m of
        Stub -> pure Stub
        By r -> By <$> (gt `by` r)
        From h@(_, (t, _, _) :$$ _) | elem t [Uid, Sym] -> do
          h@(Our ht _) <- elabTm Prop h
          demand (PROVE ht)
          fromSubs gt ht
          return (From h)
        From h -> gripe $ FromNeedsConnective h
        MGiven -> MGiven <$ given gt
      ns <- chkSubProofs ps
      let proven = case m of {Stub -> False; _ -> all happy ns}
      return $ Prove g m (Keep, proven) ns src
    Nothing -> return $ Prove g (fmap Your m) (Junk Mardiness, True)
      (fmap subPassive ps) src

happy :: SubProve Anno TmR -> Bool
happy (_ ::- Prove _ _ (_, b) _ _) = b
happy _ = True
 
-- checking subproofs amounts to validating them,
-- then checking which subgoals are covered,
-- generating stubs for those which are not,
-- and marking as surplus those subproofs which do
-- not form part of the cover
chkSubProofs
  :: Bloc (SubProve () Appl)         -- subproofs coming from user
  -> AM (Bloc (SubProve Anno TmR))   -- reconstruction
chkSubProofs ps = do
  ps <- traverse validSubProof ps
  ss <- demands
  (qs, us) <- cover ss (fmap (False,) ps)
  vs <- extra us
  return $ glom (fmap squish qs) vs
 where
  cover
    :: [Subgoal]  -- subgoals to cover
    -> Bloc (Bool, SubProve Anno TmR)  -- (used yet?, subproof)
    -> AM (Bloc (Bool, SubProve Anno TmR)  -- ditto
          , [Subgoal]                      -- undischarged subgoals
          )
  cover [] qs = return (qs, [])
  cover (t : ts) qs = cope (cover1 t qs)
    (\ _ -> cover ts qs >>= \ (qs, ts) -> return (qs, t : ts))
    $ cover ts
  cover1 :: Subgoal -> Bloc (Bool, SubProve Anno TmR)
         -> AM (Bloc (Bool, SubProve Anno TmR))
  cover1 t (_ :-/ Stop) = gripe FAIL
  cover1 t (g :-/ (b, p) :-\ qs) = cope (covers t p)
    (\ _ -> ((g :-/) . ((b, p) :-\ )) <$> cover1 t qs)
    $ \ _ -> return $ (g :-/ (True, p) :-\ qs)
  covers :: Subgoal -> SubProve Anno TmR -> AM ()
  covers t ((_, hs) ::- Prove g m (Keep, _) _ _) = subgoal t $ \ t -> do
    g <- mayhem $ my g
    traverse ensure hs
    equal Prop (g, t)
   where
    ensure (Given h) = mayhem (my h) >>= given
  covers t _ = gripe FAIL
  squish :: (Bool, SubProve Anno TmR) -> SubProve Anno TmR
  squish (False, gs ::- Prove g m (Keep, _) ss src) =
    gs ::- Prove g m (Junk Surplus, True) ss src
  squish (_, q) = q
  extra :: [Subgoal] -> AM [SubProve Anno TmR]
  extra [] = return []
  extra (u : us) = cope (subgoal u obvious)
    (\ _ -> (need u :) <$> extra us)
    $ \ _ -> extra us
  obvious s
    =   given s
    <|> given FALSE
    <|> equal Prop (s, TRUE)
  need (PROVE g) =
    ([], []) ::- Prove (My g) Stub (Need, False)
      ([] :-/ Stop) ([], [])
  need (GIVEN h u) = case need u of
    (_, gs) ::- p -> ([], Given (My h) : gs) ::- p
    s -> s
  glom :: Bloc x -> [x] -> Bloc x
  glom (g :-/ p :-\ gps) = (g :-/) . (p :-\) . glom gps
  glom end = foldr (\ x xs -> [] :-/ x :-\ xs) end

subgoal :: Subgoal -> (Tm -> AM x) -> AM x
subgoal (GIVEN h g) k = h |- subgoal g k
subgoal (PROVE g) k = k g

validSubProof
  :: SubProve () Appl
  -> AM (SubProve Anno TmR)
validSubProof ((srg, Given h : gs) ::- p@(Prove sg sm () sps src)) =
  cope (elabTm Prop h)
    (\ gr -> return $ (srg, map (fmap Your) (Given h : gs)) ::-
      Prove (Your sg) (fmap Your sm) (Junk gr, True)
        (fmap subPassive sps) src)
    $ \ h@(Our ht _) -> do
      (srg, gs) ::- p <- ht |- validSubProof ((srg, gs) ::- p)
      return $ (srg, Given h : gs) ::- p
validSubProof ((srg, []) ::- Prove sg sm () sps src) =
  cope (elabTm Prop sg)
    (\ gr -> return $ (srg, []) ::- Prove  (Your sg) (fmap Your sm) (Junk gr, True)
      (fmap subPassive sps) src)
    $ \ sg -> ((srg, []) ::-) <$> chkProof sg sm sps src
validSubProof (SubPGuff ls) = return $ SubPGuff ls


fromSubs
  :: Tm      -- goal
  -> Tm      -- fmla
  -> AM ()
fromSubs g f = map snd {- ignorant -} <$> invert f >>= \case
  [[s]] -> flop s g
  rs -> mapM_ (demand . foldr (GIVEN . propify) (PROVE g)) rs
 where
  flop (PROVE p)   g = demand . GIVEN p $ PROVE g
  flop (GIVEN h s) g = do
    demand $ PROVE h
    flop s g
  propify (GIVEN s t) = s :-> propify t
  propify (PROVE p)   = p


{-
testChkProof :: String -> [Prove Anno TmR]
testChkProof = foldMap (bof . fst) . raw (fixities mySetup) where
  bof (RawProof (Prove gr mr () ps src)) = case runAM (chkProof g mr ps src) mySetup ga of
    Right p -> [p]
    Left _  -> []
   where
    (ga, g) = applScoTm gr
  bof _ = []
-}

pout :: LayKind -> Prove Anno TmR -> AM (Odd String [LexL])
pout k p@(Prove g m (s, n) ps (h, b)) = let k' = scavenge b in case s of
  Keep -> do
    blk <- psout k' ps
    return $ (rfold lout (h `prove` n) . whereFormat b ps
             $ format k' blk)
             :-/ Stop
  Need -> do
    g <- ppTmR AllOK g
    blk <- psout k' ps
    return $ (("prove " ++) . (g ++) . (" ?" ++) . whereFormat b ps
             $ format k' blk)
             :-/ Stop
  Junk e -> do
    e <- ppGripe e
    return $
      ("{- " ++ e) :-/ [(Ret, (0,0), "\n")] :-\
      (rfold lout h . rfold lout b $ "") :-/ [(Ret, (0,0), "\n")] :-\
      "-}" :-/ Stop
 where
   ((Key, p, s) : ls) `prove` n | elem s ["prove", "proven"] =
     (Key, p, "prove" ++ if n then "n" else "") : ls
   (l : ls) `prove` n = l : (ls `prove` n)
   [] `prove` n = [] -- should never happen
   
   psout :: LayKind -> Bloc (SubProve Anno TmR) -> AM (Bloc String)
   psout k (g :-/ Stop) = return $ g :-/ Stop
   psout k (g :-/ SubPGuff [] :-\ h :-/ r) = psout k ((g ++ h) :-/ r)
   psout k (g :-/ p :-\ gpo) =
     (g :-/) <$> (ocato <$> subpout k p <*> psout k gpo)

   subpout :: LayKind -> SubProve Anno TmR -> AM (Odd String [LexL])
   subpout _ (SubPGuff ls)
     | all gappy ls = return $ rfold lout ls "" :-/ Stop
     | otherwise = return $ ("{- " ++ rfold lout ls " -}") :-/ Stop
   subpout _ ((srg, gs) ::- Prove _ _ (Junk e, _) _ (h, b)) = do
     e <- ppGripe e
     return $
       ("{- " ++ e) :-/ [] :-\
       (rfold lout srg . rfold lout h . rfold lout b $ "") :-/ [] :-\
       "-}" :-/ Stop
   subpout k ((srg, gs) ::- p) = fish gs (pout k p) >>= \case
     p :-/ b -> (:-/ b) <$>
       ((if null srg then givs gs else pure $ rfold lout srg) <*> pure p)
    where
     fish [] p = p
     fish (Given h : gs) p = case my h of
       Nothing -> fish gs p
       Just h -> h |- fish gs p
     givs :: [Given TmR] -> AM (String -> String)
     givs gs = traverse wallop gs >>= \case
       [] -> return id
       g : gs -> return $ 
         ("given " ++) . (g ++) . rfold comma gs (" " ++)
       where
         wallop :: Given TmR -> AM String
         wallop (Given g) = ppTmR AllOK g
         comma s f = (", " ++) . (s ++) . f
   whereFormat :: [LexL] -> Bloc x -> String -> String
   whereFormat ls xs pso = case span gappy ls of
     (g, (T (("where", k) :-! _), _, _) : rs) ->
       rfold lout g . ("where" ++) . (pso ++) $ rfold lout rs ""
     _ -> case xs of
       [] :-/ Stop -> ""
       _ -> " where" ++ pso

   format :: LayKind -> Bloc String -> String
   format k gso@(pre :-/ _) = case k of
     Denty d
       | not (null pre) && all horiz pre ->
         bracy True (";\n" ++ replicate d ' ') (embrace gso) ""
       | otherwise     -> denty ("\n" ++ replicate (d - 1) ' ') gso ""
     Bracy -> bracy True ("; ") gso ""
    where
     bracy :: Bool {-first?-} -> String -> Bloc String
        -> String -> String
     bracy b _ (g :-/ Stop)
       | null g    = (if b then (" {" ++) else id) . ("}" ++)
       | otherwise = rfold lout g
     bracy b sepa (g :-/ s :-\ r) =
       (if null g
          then ((if b then " {" else sepa) ++)
          else rfold lout g)
       . (s ++)
       . bracy False (if semic g then rfold lout g "" else sepa) r
     denty sepa (g :-/ Stop) = rfold lout g -- which should be empty
     denty sepa (g :-/ s :-\ r) =
       (if null g then (sepa ++) else rfold lout g) . (s ++) . denty sepa r

   scavenge
     :: [LexL]   -- first nonspace is "where" if input had one
     -> LayKind  -- to be used
   scavenge ls = case span gappy ls of
     (_, (T (("where", k) :-! _), _, _) : _) | k /= Empty -> k
     _ -> case k of
       Denty d -> Denty (d + 2)
       Bracy   -> Bracy

   horiz :: LexL -> Bool
   horiz (Ret, _, _) = False
   horiz (Cmm, _, s) = all (not . (`elem` "\r\n")) s
   horiz _ = True

   semic :: [LexL] -> Bool
   semic = go False where
     go b [] = b
     go b ((Cmm, _, _) : _) = False
     go b (g : ls) | gappy g = go b ls
     go False ((Sym, _, ";") : ls) = go True ls
     go _ _ = False

   embrace :: Bloc String -> Bloc String
   embrace (g :-/ Stop) = g :-/ Stop
   embrace (g :-/ s :-\ r) = mang g (++ [(Sym, (0,0), "{")]) :-/ s :-\ go r
     where
     go (h :-/ Stop) = mang h clos :-/ Stop
     go (g :-/ s :-\ h :-/ Stop) =
       mang g sepa :-/ s :-\ mang h clos :-/ Stop
     go (g :-/ s :-\ r) = mang g sepa :-/s :-\ go r
     mang [] f = []
     mang g  f = f g
     clos ls = (Sym, (0,0), "}") :ls
     sepa ls = (Sym, (0,0), ";") : ls ++ [(Spc, (0,0), " ")]

filth :: String -> String
filth s = bifoldMap (($ "") . rfold lout) yuk (raw (fixities mySetup) s) where
  yuk (RawProof (Prove gr mr () ps src), ls) = case runAM go mySetup init of
    Left e -> case runAM (ppGripe e) mySetup init of
      Left _ -> "{- " ++ show e ++ "\n" ++ rfold lout ls "\n-}"
      Right (e, _) ->
         "{- " ++ e ++ "\n" ++ rfold lout ls "\n-}"
    Right (s, _) -> s
   where
    go :: AM String
    go = do
      g <- impQElabTm Prop gr
      bifoldMap id (($ "") . rfold lout) <$> 
           (chkProof g mr ps src >>= pout (Denty 1))
  yuk (RawSewage, ls) = "{- don't ask\n" ++ rfold lout ls "\n-}"
  yuk (_, ls) = rfold lout ls ""
  init :: AskState
  init = AskState
    { context = myContext
    , root    = (B0, 0)
    }