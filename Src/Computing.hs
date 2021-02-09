------------------------------------------------------------------------------
----------                                                          ----------
----------     Ask.Src.Computing                                    ----------
----------                                                          ----------
------------------------------------------------------------------------------

{-# LANGUAGE
    LambdaCase
  , PatternSynonyms
  , TupleSections
#-}

module Ask.Src.Computing where

import Ask.Src.Bwd
import Ask.Src.Tm
import Ask.Src.Context


------------------------------------------------------------------------------
--  Sizes
------------------------------------------------------------------------------

pattern Size = TC "'Size" []
pattern Top = TC "'T" []
pattern Wee x = TC "'<" [x]


------------------------------------------------------------------------------
--  Head normalisation
------------------------------------------------------------------------------

chkHnf ::
  ( Chk  -- the type
  , Chk  -- the term
  ) -> AM Chk
chkHnf (trg, TE e) = do
  (e, src) <- hnfSyn e
  ship e src trg
chkHnf (Size, Wee s) = chkHnf (Size, s) >>= \ s -> case s of
  TC _ _  -> return s
  _       -> return $ Wee s
chkHnf (_, t) = return t

hnfSyn :: Syn -> AM (Syn, Chk)
hnfSyn (TV _) = gripe Mardiness
hnfSyn e@(TP d) = case wot d of
  Green _ e  -> hnfSyn e
  _          -> return (e, typ d)
hnfSyn (tm ::: ty) = do
  ty <- chkHnf (Type, ty)
  tm <- chkHnf (ty, tm)
  return (tm ::: ty, ty)
hnfSyn (e :$ s) = do
  (e, ty) <- hnfSyn e
  case ty of
    TC "->" [dom, ran] -> case e of
      TB b ::: _ -> hnfSyn $ (b // (s ::: dom)) ::: ran
      _ -> return (e :$ s, ran)
{-
    TC d ss -> case s of
      TC c [TB m, tel, s'] -> let ty = m // e in case e of
        TC c' rs ::: _
          | c == c' -> do
              (_, t) <- runTell tel rs
              return (t ::: ty, ty)
          | otherwise -> hnfSyn (e :$ s')
        _ -> return (e :$ s, m // e)
      _ -> gripe Mardiness
-}
    _ -> gripe Mardiness

ship :: Syn -> Chk -> Chk -> AM Chk
ship e src trg = subtype src trg >>= \case
  True -> case e of
    t ::: _ -> return t
    _ -> return $ TE e
  False -> case (e, src, trg) of
    (e, s :-> t, s' :-> t') -> return . TB . L . TE $
      TE (e :$ TE ((TE (TV 0) ::: s))) ::: t'
    (TC c ts ::: _, TC d ss, TC d' ss') | d == d' -> do
      tel  <- conTell (d, ss)  c
      tel' <- conTell (d, ss') c
      TC c <$> ships ts tel tel'
    _ -> return (TE (TE e ::: trg))

ships :: [Chk] -> Chk -> Chk -> AM [Chk]
ships [] _ _ = return []
ships (t : ts) (Sg _ s b) (Sg _ s' b') = do
  let e = t ::: s
  t' <- ship e s s'
  ts' <- ships ts (b // e) (b' // (t' ::: s'))
  return (t' : ts')
ships ts (Pr _ t) (Pr _ t') = ships ts t t'
ships _ _ _ = gripe Mardiness

subtype :: Chk -> Chk -> AM Bool
subtype x y = do
  x <- chkHnf (Type, x)
  y <- chkHnf (Type, y)
  case (x, y) of
    (s :-> t, s' :-> t') -> (&&) <$> subtype s' s <*> subtype t t'
    (TC d (i : ss), TC e (j : ts)) | d == e -> isData d >>= \case
      True -> sizle i j >>= \case
        False -> return False
        True  -> equal Type (TC d (j : ss), TC d (j : ts))
      False -> equal Type (x, y)
    _ -> equal Type (x, y)

isData :: String  -- must be a type constructor
       -> AM Bool
isData d = con ("Type", d) >>= \case
  Re (Sg _ Size _) -> return True
  _ -> return False

sizle :: Chk -> Chk -> AM Bool
sizle i j = chkHnf (Size, j) >>= \case
  Top -> return True
  j -> chkHnf (Size, i) >>= \ i -> case (i, j) of
    (Wee i, Wee j) -> equal Size (i, j)
    (Wee i, j)     -> equal Size (i, j)
    _              -> return False

equal :: Chk -> (Chk, Chk) -> AM Bool
equal ty (a, b) = do
  ty <- chkHnf (Type, ty)
  a <- chkHnf (ty, a)
  b <- chkHnf (ty, b)
  case ty of
    s :-> t -> do
      K b <- (Nothing, s) |- \ v ->
        equal t (TE ((a ::: ty) :$ TE v), TE ((b ::: ty) :$ TE v))
      return b
    TC d ss -> case (a, b) of
      (TC c ts, TC c' ts') | c == c' -> do
        tel <- conTell (d, ss) c
        eqTel tel ts ts'
      _ -> return False
    _ -> case (a, b) of
      (TE e, TE e') -> eqSyn e e' >>= \case
        Just _ -> return True
        _      -> return False
      _ -> return False

eqTel :: Chk -> [Chk] -> [Chk] -> AM Bool
eqTel _ [] [] = return True
eqTel (Sg _ s b) (u : us) (v : vs) = (&&)
  <$> equal s (u, v)
  <*> eqTel (b // (u ::: s)) us vs
eqTel (Pr p t) us vs = eqTel t us vs
eqTel _ _ _ = return False

eqSyn :: Syn -> Syn -> AM (Maybe Chk)
eqSyn (TP x) (TP y) | nom x == nom y = return (Just (typ x))
eqSyn (e :$ s) (f :$ t) = eqSyn e f >>= \case
  Just (a :-> b) -> equal a (s, t) >>= \case
    True -> return (Just t)
    False -> return Nothing
  _ -> return Nothing
eqSyn (a ::: s) (b ::: t) = equal Type (s, t) >>= \case
  False -> return Nothing
  True -> equal s (a, b) >>= \case
    True -> return (Just s)
    False -> return Nothing
eqSyn _ _ = return Nothing


------------------------------------------------------------------------------
-- Getting the telescope for a constructor's arguments
------------------------------------------------------------------------------

conTel
  :: (Syn -> (Con, [Tm]) -> Con -> AM [Tm]) -- match failure recovery
  -> (Pr -> AM ())  -- that which demands a proof obligation
  -> (Con, [Tm])  -- the type constructor and its arguments
  -> Con          -- the value constructor we want to know about
  -> AM (Tel ())  -- the telescope which should eat the constructor's fields
conTel ha de (d, ss) c = do
  tel <- con (d, c)
  snd <$> runTel ha de tel ss

runTel
  :: (Syn -> (Con, [Tm]) -> Con -> AM [Tm]) -- match failure recovery
  -> (Pr -> AM ())  -- that which demands a proof obligation
  -> Tel Tm   -- the thing that eats
  -> [Tm]     -- its food
  -> AM ( [(Ty, Tm)]  -- its trace
        , Tm          -- its output
        )
runTel ha de = go B0 where
  go ytz (Re r)     []       = return (ytz <>> [], r)
  go ytz (Sg _ s b) (x : xs) = go (ytz :< (s, x)) (b // (x ::: s)) xs
  go ytz (Pr p t)   xs       = de p >> go ytz t xs
  go ytz (TE ((t ::: y) :$ TC c [tel])) xs = do
    y@(TC d ss) <- chkHnf (Type, y)
    rs <- chkHnf (y, t) >>= \case
      TC c' rs | c == c' -> return rs
      TE e -> ha e (d, ss) c
      _ -> gripe Mardiness
    (_, tel) <- go B0 tel rs
    go ytz tel xs

-- and when we're supposed to have well typed stuff already

conTell :: (Con, [Tm]) -> Con -> AM (Tel ())
runTell :: Tel Tm -> [Tm] -> AM ([(Ty, Tm)], Tm)
conTell = conTel (\ _ _ _ -> gripe Mardiness) (\ _ -> return ())
runTell = runTel (\ _ _ _ -> gripe Mardiness) (\ _ -> return ())