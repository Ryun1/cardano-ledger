{-# OPTIONS_GHC -Wno-unused-matches #-}


{-# LANGUAGE GADTs, MultiParamTypeClasses #-}
{-# LANGUAGE FlexibleContexts, FlexibleInstances, FunctionalDependencies  #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE DeriveGeneric           #-}
{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE RankNTypes #-}


module Control.Iterate.SetAlgebra where

import Prelude hiding(lookup)

import qualified Data.Map.Strict as Map
import Data.Map.Strict(Map)
import Data.Map.Internal(Map(..),link2)

import qualified Data.Set as Set

import Data.List(sortBy)
import qualified Data.List as List

import Control.Iterate.Collect

import Text.PrettyPrint.ANSI.Leijen(Doc,text,(<+>),align,vsep,parens)

-- ==================================================================================================
-- In order to build typed Exp (which are a typed deep embedding) of Set operations, we need to know
-- what kind of basic types of Maps and Sets can be embedded. Every Basic type has a few operations
-- for adding and removing key-value pairs. The Maps and Sets of this algebra are functional in that
-- every key has exactly one value associated with it.
-- ===================================================================================================

class Iter f => Basic f where
  addpair:: (Ord k) => k -> v -> f k v -> f k v
  addpair k v f = addkv (k,v) f (\ a b -> a)
  addkv :: Ord k => (k,v) -> f k v -> (v -> v -> v) -> f k v
  removekey:: (Ord k) => k -> f k v -> f k v
  emptyc:: Ord k => f k v
  emptyc = error ("emptyc only works on some types.")

-- ========== Basic List ==============

instance Basic List where
   addpair k v (List xs) = List(insert xs) where
       insert [] = [(k,v)]
       insert ((key,u):ys) = if k==key then ((k,v):ys) else (k,u):(insert ys)
   addkv (k,v) (List xs) comb = List(insert xs) where
       insert [] = [(k,v)]
       insert ((key,u):ys) = if k==key then ((k,comb u v):ys) else (k,u):(insert ys)
   removekey k (List xs) = List(remove xs) where
       remove [] = []
       remove ((key,u):ys) = if key==k then ys else (k,u):(remove ys)
   emptyc = (List [])


-- ================ Basic Single ===============
-- The Single type encode 0 or 1 pairs. Iteration is trivial. Succeeds only once.

data Single k v where
  Single :: k -> v -> Single k v
  Fail :: Single k v
  SetSingle :: k -> Single k ()

firstwins :: Bool
firstwins = False

instance Basic Single where
  addkv (k,v) set comb =
     if firstwins     -- Since we can only store one key, we have to choose who wins
        then case set of
               (Single a b) -> if k==a then Single a (comb v b) else (Single a b)
               (SetSingle a) -> SetSingle a
               Fail ->  Single k v
        else case set of
               (Single a b) -> if k==a then Single a (comb v b) else (Single k v)
               (SetSingle a) -> SetSingle k
               Fail ->  Single k v

  removekey key (Single a b) = if key==a then Fail else (Single a b)
  removekey key (SetSingle a) = if key==a then Fail else (SetSingle a)
  removekey key Fail = Fail
  emptyc = Fail


-- ============== Basic Map =========================

instance Basic Map.Map where
  addpair = Map.insertWith (\x _y -> x)
  addkv (k,v) m comb = Map.insertWith comb k v m
  removekey k m = Map.delete k m
  emptyc = Map.empty


-- =================== Basic BiMap =====================
-- For Bijections we define (BiMap v k v).  Reasons we can't use (Data.Bimap k v)
-- 1) We need to enforce that the second argument `v` is in the Ord class, when making it an Iter instance.
-- 2) The constructor MkBimap is not exported, so we can't roll our own operations necessary to get good asymptotic performance
-- 3) Missing operation 'restrictkeys' and 'withoutkeys' make performant versions of operations  ◁ ⋪ ▷ ⋫ hard.
-- 4) Missing operation 'union', make performant versions of ∪ and ⨃ hard.


data BiMap v a b where MkBiMap:: (v ~ b) => !(Map.Map a b) -> !(Map.Map b a) -> BiMap v a b
                                --  ^   the 1st and 3rd parameter must be the same:   ^   ^

instance Ord v => Basic (BiMap v) where
  addpair k y (MkBiMap m1 m2) = MkBiMap (Map.insertWith (\x _y -> x) k y m1)  (Map.insertWith (\x _y -> x) y k m2)
  addkv (k,v) (MkBiMap f b) comb =
     case Map.lookup k f of
       Nothing -> MkBiMap (Map.insert k v f) (Map.insert v k b)
       Just v2 -> MkBiMap (Map.insert k v3 f) (Map.insert v3 k (Map.delete v2 b))
          where v3 = comb v v2
  removekey k (m@(MkBiMap m1 m2)) =  -- equality constraint (a ~ v) from (BiMap a k v) into scope.
     case Map.lookup k m1 of
        Just v -> MkBiMap (Map.delete k m1) (Map.delete v m2)
        Nothing -> m
  emptyc = error ("emptyc cannot be defined for BiMap, use the variable: biMapEmpty :: BiMap v k v")


biMapEmpty :: BiMap v k v
biMapEmpty = MkBiMap Map.empty Map.empty

biMapFromList:: (Ord k,Ord v) => [(k,v)] -> BiMap v k v
biMapFromList xs = foldr (\ (k,v) ans -> addpair k v ans) biMapEmpty xs

-- This synonym makes (BiMap v k v) appear as an ordinary Binary type contructor: (Bimap k v)
type Bimap k v = BiMap v k v

-- This operation is very fast (Log n) on BiMap, but extremely slow on other collections.
removeval:: (Ord k, Ord v) => v -> BiMap v k v -> BiMap v k v
removeval v (m@(MkBiMap m1 m2)) =
     case Map.lookup v m2 of
        Just k -> MkBiMap (Map.delete k m1) (Map.delete v m2)
        Nothing -> m

-- ================= Basic Set =====================

data Sett k v where Sett :: (Set.Set k) -> Sett k ()

instance Basic Sett where
  addpair key unit (Sett m) = Sett(Set.insert key m)
  addkv (k,unit) (Sett m) comb = Sett(Set.insert k m)  -- We can ignore comb since there is only one function at type: () -> () -> ()
  removekey k (Sett m) = Sett(Set.delete k m)
  emptyc = error ("Sett Set.empty has type (Sett k ()) and it needs type (Sett k v)")


-- ============================================================================
-- Every iterable type type forms an isomorphism with some Base type. For most
-- Base types the isomorphism is the identity in both directions, but for some,
-- like List and Sett, the embeddings are not the trivial identities because the
-- concrete types are not binary type constructors. The Embed class also allows
-- us to add 'newtypes' which encode some Base type to the system.
-- ============================================================================

class Embed concrete base | concrete -> base where
  toBase :: concrete -> base
  fromBase :: base -> concrete

instance Ord k => Embed [(k,v)] (List k v) where
   toBase xs = List(sortBy (\ x y -> compare (fst x) (fst y)) xs)
   fromBase (List xs) = xs

instance Embed (Set.Set k) (Sett k ()) where
   toBase xs = Sett xs
   fromBase (Sett xs) = xs

instance Embed (Map.Map k v) (Map.Map k v) where
   toBase xs = xs
   fromBase xs = xs

instance Embed (BiMap v k v) (BiMap v k v) where
   toBase xs = xs
   fromBase xs = xs

instance Embed (Single k v) (Single k v) where
   toBase xs = xs
   fromBase xs = xs

-- Necessary when asking Boolean queries like: (⊆),(∈),(∉)
instance Embed Bool Bool where
   toBase xs = xs
   fromBase xs = xs

-- ================= The Iter class =================================================
-- The Set algebra include types that encode finite maps of some type. They
-- have a finite domain, and for each domain element they pair a single range
-- element. We are interested in those finite maps that can iterate their
-- pairs in ascending domain order. The operations are: `nxt` and `lub` .
-- lub can skip over many items in sub-linear time, it can make things really fast.
-- Many finite maps can support a support lub operation in sub-linear time. Some examples:
-- Balanced binary trees, Arrays (using binary search), Tries, etc. There are basic and compound
-- Iter instances. Compound types include components with types that have Iter instances.
-- ===================================================================================

class Iter f where
  nxt:: f a b -> Collect (a,b,f a b)
  lub :: Ord k => k -> f k b -> Collect (k,b,f k b)

  -- The next few methods can all be defined via nxt and lub, but for base types there often exist
  -- much more efficent means, so the default definitions should be overwritten for such basic types.
  -- For compound types with Guards, these are often the only way to define them.

  hasNxt :: f a b -> Maybe(a,b,f a b)
  hasNxt f = hasElem (nxt f)
  hasLub :: Ord k => k -> f k b -> Maybe(k,b,f k b)
  hasLub a f = hasElem (lub a f)
  haskey:: Ord key => key -> f key b -> Bool
  haskey k x = case hasLub k x of { Nothing -> False; Just (key,_,_) -> k==key}
  isnull:: f k v -> Bool
  isnull f = isempty(nxt f)
  lookup:: Ord key => key -> f key rng -> Maybe rng
  lookup k x = case hasLub k x of { Nothing -> Nothing; Just (key,v,_) -> if k==key then Just v else Nothing}
  element :: (Ord k) => k -> f k v -> Collect ()
  element k f = when (haskey k f)


-- ============== Iter List ==============
data List k v where  List :: Ord k => [(k,v)]  -> List k v

instance Iter List where                      -- List is the only basic instance with non-linear nxt and lub. It also depends on
   nxt (List []) = none                       -- key-value pairs being stored in ascending order. For small Lists (10 or so elements) this is OK.
   nxt (List ((k,v):xs)) = one(k,v,List xs)
   lub k (List xs) = case dropWhile (\ (key,v) -> key < k) xs of
                       [] -> none
                       ((key,v):ys) -> one (key,v,List ys)
   isnull (List xs) = null xs
   lookup k (List xs) = List.lookup k xs
   hasNxt (List []) = Nothing
   hasNxt (List (((k,v):ps))) = Just(k,v,List ps)


-- =============== Iter Single ==================

instance Iter Single where
  nxt (Single k v) = Collect(\ ans f -> f (k,v,Fail) ans)
  nxt (SetSingle k) = Collect(\ ans f ->  f (k,(),Fail) ans)
  nxt Fail = Collect(\ ans f -> ans)
  lub key (Single k v) = Collect(\ ans f -> if k<=key then f (k,v,Fail) ans else ans)
  lub key (SetSingle k) = Collect(\ ans f -> if k<=key then f(k,(),Fail) ans else ans)
  lub key Fail = Collect(\ ans f -> ans)
  haskey k (SetSingle a) = k==a
  haskey k (Single a b) = k==a
  haskey k Fail = False
  isnull Fail = True
  isnull _ = False
  lookup k (SetSingle a) = if k==a then Just() else Nothing
  lookup k (Single a b) = if k==a then Just b else Nothing
  lookup k Fail = Nothing

instance (Show k,Show v) => Show (Single k v) where
  show (Single k v) = "(Single "++show k ++ " "++show v++")"
  show (SetSingle k) = "(SetSingle "++show k++")"
  show Fail = "Fail"

-- ============= Iter Sett ===============

instance Iter Sett where
  nxt (Sett m) = Collect (\ ans f -> if Set.null m then ans else let (k,nextm) = Set.deleteFindMin m in f (k,(),Sett nextm) ans)
  lub key (Sett m) =
      Collect (\ ans f -> if Set.null m
                             then ans
                             else case Set.splitMember key m of   -- NOTE in Log time, we skip over all those tuples in _left
                                     (_left,True,right) -> f (key,(),Sett right) ans
                                     (_left,False,right) -> if Set.null right
                                                        then ans
                                                        else let (k,nextm) = Set.deleteFindMin right in f (k,(),Sett  nextm) ans)
  haskey key (Sett m) = Set.member key m
  isnull (Sett x) = Set.null x
  lookup k (Sett m) = if Set.member k m then Just() else Nothing


-- ================== Iter Map ===============

instance Iter Map.Map where
  nxt m = Collect (\ ans f ->
     case Map.minViewWithKey m of
        Nothing -> ans
        Just((k,v),nextm) -> f (k,v,nextm) ans)
  lub key m = Collect (\ ans f ->
     case Map.splitLookup key m of                  -- NOTE in Log time, we skip over all those tuples in _left
       (_left,Just v,right) -> f (key,v,right) ans
       (_left,Nothing,Tip) -> ans
       (_left,Nothing,right) -> f (k,v,m3) ans
           where ((k,v),m3) = Map.deleteFindMin right)
  haskey x m = case Map.lookup x m of Just _ -> True; Nothing -> False
  isnull = Map.null
  lookup = Map.lookup


-- ===========================================================
-- Some times we need to write our own version of functions
-- over  Map.Map that do not appear in the library
-- A version of Map.withoutKeys where both parts are Map.Map
-- ============================================================

noKeys :: Ord k => Map k a -> Map k b -> Map k a
noKeys Tip _ = Tip
noKeys m Tip = m
noKeys m (Bin _ k _ ls rs) = case Map.split k m of
  (lm, rm) -> link2 lm' rm'     -- We know `k` is not in either `lm` or `rm`
     where !lm' = noKeys lm ls
           !rm' = noKeys rm rs
{-# INLINABLE noKeys #-}


-- ============== Iter BiMap ====================

instance Ord v => Iter (BiMap v) where
  nxt (MkBiMap left right) = Collect (\ ans f ->
     case Map.minViewWithKey left of
        Nothing -> ans
        Just((k,v),nextm) -> f (k,v,MkBiMap nextm right) ans)
  lub key (MkBiMap forward backward) = Collect (\ ans f ->
     case Map.splitLookup key forward of           -- NOTE in Log time, we skip over all those tuples in _left
       (_left,Just v,right) -> f (key,v,MkBiMap right backward) ans
       (_left,Nothing,Tip) -> ans
       (_left,Nothing,right) -> f (k,v,MkBiMap m3 backward) ans
           where ((k,v),m3) = Map.deleteFindMin right )
  isnull (MkBiMap f g) = isnull f
  lookup x (MkBiMap left right) = Map.lookup x left
  haskey k (MkBiMap left right) = haskey k left


-- ===============================================================================================
-- BaseRep witnesses Basic types. I.e. those types that are instances of both Basic and Iter.
-- It is used in constructors 'Base' and 'BaseD' and functions 'materialize' and 'fromList'
-- ===============================================================================================

data BaseRep f k v where
   MapR::    Basic Map.Map => BaseRep Map.Map k v
   SetR::    Basic Sett    => BaseRep Sett k ()
   ListR::   Basic List    => BaseRep List k v
   SingleR:: Basic Single  => BaseRep Single k v
   BiMapR::  (Basic (BiMap v),Ord v) => BaseRep (BiMap v) k v


-- ==========================================================================
-- The most basic operation of iteration, where (Iter f) is to use the 'nxt'
-- operator on (f k v) to create a (Collect k v). The two possible
-- ways to produce their elements are in LIFO or FIFO order.
-- ===========================================================================

lifo :: Iter f => f k v -> Collect (k,v)
lifo x = do { (k,v,x2) <- nxt x; front (k,v) (lifo x2) }

fifo :: Iter f => f k v -> Collect (k,v)
fifo x = do { (k,v,x2) <- nxt x; rear (fifo x2) (k,v)}


-- ================================================================================================
-- | The self typed GADT: Exp, that encodes the shape of Set expressions. A deep embedding.
-- Exp is a typed Symbolic representation of queries we may ask. It allows us to introspect a query
-- The strategy is to
-- 1) Define Exp so all queries can be represented.
-- 2) Define smart constructors that "parse" the surface syntax, and build a typed Exp
-- 3) Write an evaluate function:  eval:: Exp t -> t
-- 4) "eval" can introspect the code and apply efficient domain and type specific translations
-- 5) Use the (Iter f) class to evaluate some Exp that can benefit from its efficient nature.
-- ===============================================================================================

data Exp t where
   Base:: (Ord k,Basic f) => BaseRep f k v -> f k v -> Exp (f k v)  -- Note the use of BaseRep to witness what Base type.
   Dom:: Ord k => Exp (f k v) -> Exp (Sett k ())
   Rng:: (Ord k,Ord v) => Exp (f k v) -> Exp (Sett v ())
   DRestrict:: (Ord k,Iter g) => Exp (g k ()) -> Exp (f k v) -> Exp (f k v)
   DExclude::  (Ord k,Iter g) => Exp (g k ()) -> Exp (f k v) -> Exp (f k v)
   RRestrict:: (Ord k,Iter g,Ord v) => Exp (f k v) -> Exp (g v ()) -> Exp (f k v)
   RExclude:: (Ord k,Iter g,Ord v) => Exp (f k v) -> Exp (g v ()) -> Exp (f k v)
   Elem :: (Ord k,Iter g,Show k) => k -> Exp(g k ()) -> Exp Bool
   NotElem ::(Ord k,Iter g, Show k) => k -> Exp(g k ()) -> Exp Bool
   Intersect :: (Ord k, Iter f, Iter g) => Exp(f k v) -> Exp(g k u) -> Exp(Sett k ())
   Subset ::  (Ord k, Iter f, Iter g) => Exp(f k v) -> Exp(g k u) -> Exp Bool
   UnionOverrideLeft:: Ord k => Exp (f k v) -> Exp (g k v) -> Exp(f k v)
   UnionPlus:: (Ord k,Num n) => Exp (f k n) -> Exp (f k n) -> Exp(f k n)
   UnionOverrideRight:: Ord k => Exp (f k v) -> Exp (g k v) -> Exp(f k v)
   Singleton:: (Ord k) => k -> v -> Exp(Single k v)
   SetSingleton:: (Ord k) => k -> Exp(Single k ())

-- =================================================================
-- | Basic types are those that can be embedded into Exp.
-- The HasExp class, encodes how to lift a Basic type into an Exp.
-- The function 'toExp' will build a typed Exp for that Basic type.
-- This will be really usefull in the smart constructors.
-- ==================================================================

class HasExp s t | s -> t where
  toExp :: s -> Exp t

-- | The simplest Base type is one that is already an Exp

instance HasExp (Exp t) t where
  toExp x = x

instance (Ord k) => HasExp (Map k v) (Map k v) where
  toExp x = Base MapR x

instance (Ord k) => HasExp (Set.Set k) (Sett k ()) where
  toExp x = Base SetR (Sett x)


instance  (Ord k) => HasExp [(k,v)] (List k v) where
  toExp l = Base ListR (List (sortBy (\ x y -> compare (fst x) (fst y)) l))

instance (Ord k) => HasExp (Single k v) (Single k v) where
  toExp x = Base SingleR x

instance (Ord k,Ord v) => HasExp (Bimap k v) (Bimap k v) where
  toExp x = Base BiMapR x

-- ==========================================================================================
-- Smart constructors build typed Exp with real values at the leaves (the Base constuctor)

-- (⊆),
-- (∩),


dom :: (Ord k,HasExp s (f k v)) => s -> Exp (Sett k ())
dom x = Dom (toExp x)

range:: (Ord k,Ord v) => HasExp s (f k v) => s -> Exp (Sett v ())
range x = Rng(toExp x)

(◁),(<|),drestrict ::  (Ord k,HasExp s1 (Sett k ()), HasExp s2 (f k v)) => s1 -> s2 -> Exp (f k v)
(◁) x y = DRestrict (toExp x) (toExp y)
drestrict = (◁)
(<|) = drestrict

(⋪),dexclude :: (Ord k,Iter g, HasExp s1 (g k ()), HasExp s2 (f k v)) => s1 -> s2 -> Exp (f k v)
(⋪) x y = DExclude (toExp x) (toExp y)
dexclude = (⋪)

(▷),(|>),rrestrict :: (Ord k,Iter g, Ord v, HasExp s1 (f k v), HasExp s2 (g v ())) => s1 -> s2 -> Exp (f k v)
(▷) x y = RRestrict (toExp x) (toExp y)
rrestrict = (▷)
(|>) = (▷)

(⋫),rexclude :: (Ord k,Iter g, Ord v, HasExp s1 (f k v), HasExp s2 (g v ())) => s1 -> s2 -> Exp (f k v)
(⋫) x y = RExclude (toExp x) (toExp y)
rexclude = (⋫)
(∈) :: (Show k, Ord k,Iter g,HasExp s (g k ())) => k -> s -> Exp Bool
(∈) x y = Elem x (toExp y)

(∉),notelem :: (Show k, Ord k,Iter g, HasExp s (g k ())) => k -> s -> Exp Bool
(∉) x y = NotElem x (toExp y)
notelem = (∉)

(∪),unionleft :: (Ord k,HasExp s1 (f k v), HasExp s2 (g k v)) => s1 -> s2 -> Exp (f k v)
(∪) x y = UnionOverrideLeft (toExp x) (toExp y)
unionleft = (∪)

(⨃),unionright :: (Ord k,HasExp s1 (f k v), HasExp s2 (g k v)) => s1 -> s2 -> Exp (f k v)
(⨃) x y = UnionOverrideRight (toExp x) (toExp y)
unionright = (⨃)

(∪+),unionplus :: (Ord k,Num n, HasExp s1 (f k n), HasExp s2 (f k n)) => s1 -> s2 -> Exp (f k n)
(∪+) x y = UnionPlus (toExp x) (toExp y)
unionplus = (∪+)

singleton :: (Ord k) => k -> v -> Exp (Single k v)
singleton k v = Singleton k v

setSingleton :: (Ord k) => k -> Exp (Single k ())
setSingleton k = SetSingleton k

(∩),intersect :: (Ord k, Iter f, Iter g, HasExp s1 (f k v), HasExp s2 (g k u)) => s1 -> s2 -> Exp (Sett k ())
(∩) x y = Intersect (toExp x) (toExp y)
intersect = (∩)

(⊆),subset :: (Ord k, Iter f, Iter g, HasExp s1 (f k v), HasExp s2 (g k u)) => s1 -> s2 -> Exp Bool
(⊆) x y = Subset (toExp x) (toExp y)
subset = (⊆)

-- =================================================================================================
-- | Symbolc functions (Fun) are data, that can be pattern matched over. They
-- 1) Represent a wide class of binary functions that are used in translating the SetAlgebra
-- 2) Turned into a String so they can be printed
-- 3) Turned into the function they represent.
-- 4) Composed into bigger functions
-- 5) Symbolically symplified
-- Here  we implement Symbolic Binary functions with upto 4 variables, which is enough for this use
-- =================================================================================================

data Pat env t where
  P1:: Pat (d,c,b,a) d
  P2:: Pat (d,c,b,a) c
  P3:: Pat (d,c,b,a) b
  P4:: Pat (d,c,b,a) a
  PPair:: Pat (d,c,b,a) a -> Pat (d,c,b,a) b ->  Pat (d,c,b,a) (a,b)

data Expr env t where
  X1:: Expr (d,c,b,a) d
  X2:: Expr (d,c,b,a) c
  X3:: Expr (d,c,b,a) b
  X4:: Expr (d,c,b,a) a
  HasKey:: (Iter f,Ord k) =>  Expr e k -> (f k v) -> Expr e Bool
  Neg :: Expr e Bool -> Expr e Bool
  Ap:: Lam(a -> b -> c) -> Expr e a -> Expr e b -> Expr e c
  EPair:: Expr e a -> Expr e b -> Expr e (a,b)
  FST:: Expr e (a,b) -> Expr e a
  SND:: Expr e (a,b) -> Expr e b
  Lit :: Show t => t -> Expr env t

-- Carefull no pattern P1, P2, P3, P4 should appear MORE THAN ONCE in a Lam.

data Lam t where
  Lam::  Pat (d,c,b,a) t -> Pat (d,c,b,a) s -> Expr (d,c,b,a) v -> Lam (t -> s -> v)
  Add :: Num n => Lam (n -> n -> n)
  Eql :: Eq t => Lam(t -> t -> Bool)
  Both:: Lam (Bool -> Bool -> Bool)
  Lift:: (a -> b -> c) -> Lam (a -> b -> c)  -- For use n the tests only!


-- ====================== Evaluating ================
env0 :: (d,c,b,a)
env0 = (undefined,undefined,undefined,undefined)

reify:: Lam t -> t
reify (Lam p1 p2 e) = \ x y -> evaluate (bind p1 x (bind p2 y env0)) e
reify Add = (+)
reify Eql = (==)
reify Both = (&&)
reify (Lift f) = f

evaluate:: (a,b,c,d) -> Expr (a,b,c,d) t -> t
evaluate (x1,x2,x3,x4) X1 = x1
evaluate (x1,x2,x3,x4) X2 = x2
evaluate (x1,x2,x3,x4) X3 = x3
evaluate (x1,x2,x3,x4) X4 = x4
evaluate env (EPair p q) = (evaluate env p, evaluate env q)
evaluate env (HasKey k datum) = haskey (evaluate env k) datum
evaluate env (Neg x) = not(evaluate env x)
evaluate env (Ap oper f g) = (reify oper) (evaluate env f) (evaluate env g)
evaluate env (FST f) = fst (evaluate env f)
evaluate env (SND f) = snd (evaluate env f)
evaluate env (Lit x) = x

-- Be carefull, if you create a lambda where P1,P2,P3, or P4, appears more than once
-- The rightmost binding of the repeated Pat will over ride the ones to the left.

bind :: Pat env t -> t -> env -> env
bind P1 v (d,c,b,a) = (v,c,b,a)
bind P2 v (d,c,b,a) = (d,v,b,a)
bind P3 v (d,c,b,a) = (d,c,v,a)
bind P4 v (d,c,b,a) = (d,c,b,v)
bind (PPair p q) (v1,v2) (d,c,b,a) = bind q v2 (bind p v1 (d,c,b,a))

-- ============= Printing in 𝜷-Normal Form =========================
type StringEnv = (String,String,String,String)

bindE :: Pat (a,b,c,d) t -> Expr (w,x,y,z) t -> StringEnv -> StringEnv
bindE P1 v (e@(d,c,b,a)) = (showE e v,c,b,a)
bindE P2 v (e@(d,c,b,a)) = (d,showE e v,b,a)
bindE P3 v (e@(d,c,b,a)) = (d,c,showE e v,a)
bindE P4 v (e@(d,c,b,a)) = (d,c,b,showE e v)
bindE (PPair p1 p2) (EPair e1 e2) env = bindE p1 e1 (bindE p2 e2 env)
bindE (PPair p1 p2) e env = bindE p2 (SND e) (bindE p1 (FST e) env)

showE :: StringEnv -> (Expr (a,b,c,d) t) -> String
showE (x,y,z,w) X1 = x
showE (x,y,z,w) X2 = y
showE (x,y,z,w) X3 = z
showE (x,y,z,w) X4 = w
showE e (EPair a b) = "("++showE e a++","++showE e b++")"
showE e (Ap (Lam p1 p2 expr) x y) = showE (bindE p2 y (bindE p1 x e)) expr
showE e (FST f) = "(fst " ++ showE e f ++ ")"
showE e (SND f) = "(snd " ++ showE e f ++ ")"
showE e (Ap oper a b) = "("++showE e a++showL e oper++showE e b++")"
showE e (HasKey k datum) = "(haskey "++showE e k++" ?)"
showE e (Neg x) = "(not "++showE e x++")"
showE e (Lit n) = show n

showL :: StringEnv -> Lam t -> String
showL e (Lam p1 p2 expr) = "\\ "++showP e p1++" "++showP e p2++" -> "++showE e expr
showL e Add = " + "
showL e Eql = " == "
showL e Both = " && "
showL e (Lift f) = "<lifted function>"

showP :: StringEnv -> (Pat any t) -> String
showP (x,y,z,w) P1 = x
showP (x,y,z,w) P2 = y
showP (x,y,z,w) P3 = z
showP (x,y,z,w) P4 = w
showP env (PPair p1 p2) = "("++showP env p1++","++showP env p2++")"

instance Show (Expr (a,b,c,d) t) where
   show x = showE ("X1","X2","X3","X4") x
instance Show (Lam t) where
   show x = showL ("X1","X2","X3","X4") x

-- ===============================================================================================================
-- An symbolic function Fun has two parts, a Lam that can be analyzed, and real function that can be applied
-- ===============================================================================================================

data Fun t = Fun (Lam t) t

-- | We can observe a Fun by showing the Lam part.

instance Show (Fun t) where
  show (Fun lam _fun) = show lam

-- ======================================================================================
-- Operations we use to manipulate Fun. Some simple ones, and some ways to compose them.
-- The great thing is the types completely decide what the operations do.
-- ======================================================================================


-- Used in projectStep, chainStep, andPStep, orStep and guardStep
apply :: Fun t -> t
apply (Fun e f) = f

-- Used in compile (UnionOverrideLeft case)
first :: Fun (v -> s -> v)
first = Fun (Lam P1 P2 X1) (\ x _y -> x)

-- Used in compile (UnionOverrideRight case)
second:: Fun (v -> s -> s)
second = Fun (Lam P1 P2 X2) (\ _x y -> y)

-- Used in compile (UnionPlus case)
plus:: Num t => Fun (t -> t -> t)
plus = (Fun Add (+))

eql :: Eq t => Fun (t -> t -> Bool)
eql = (Fun Eql (==))

constant:: Show c => c -> Fun(a -> b -> c)
constant c = Fun (Lam P1 P2 (Lit c)) (\ x y -> c)

-- Used in compile (RExclude RRestrict cases)
rngElem:: (Ord rng,Iter f) => f rng v -> Fun(dom -> rng -> Bool)
rngElem realset = Fun  (Lam P1 P2 (HasKey X2 realset)) (\ x y -> haskey y realset)  -- x is ignored and realset is supplied

domElem:: (Ord dom,Iter f) => f dom v -> Fun(dom -> rng -> Bool)
domElem realset = Fun  (Lam P1 P2 (HasKey X1 realset)) (\ x y -> haskey x realset)  -- x is ignored and realset is supplied

rngFst:: Fun(x -> (a,b) -> a)
rngFst = Fun (Lam P1 (PPair P2 P3) X2) (\ x (a,b) -> a)

rngSnd:: Fun(x -> (a,b) -> b)
rngSnd = Fun (Lam P1 (PPair P2 P3) X3) (\ x y -> snd y)

compose1 :: Fun (t1 -> t2 -> t3) -> Fun (t1 -> t4 -> t2) -> Fun (t1 -> t4 -> t3)
compose1 (Fun e1 f1) (Fun e2 f2) = Fun (Lam P1 P2 (Ap e1 X1 (Ap e2 X1 X2))) (\ a b -> f1 a (f2 a b))

compSndL:: Fun(k -> (a,b) -> c) -> Fun(k -> d -> a) -> Fun(k -> (d,b) -> c)
compSndL (Fun m mf) (Fun g mg) = Fun (Lam P1 (PPair P2 P3) (Ap m X1 (EPair (Ap g X1 X2) X3))) (\ x (a,b) -> mf x (mg x a,b))

compSndR:: Fun(k -> (a,b) -> c) -> Fun(k -> d -> b) -> Fun(k -> (a,d) -> c)
compSndR (Fun m mf) (Fun g mg) = (Fun (Lam P1 (PPair P2 P3) (Ap m X1 (EPair X2 (Ap g X1 X3)))) (\ x (a,b) -> mf x (a,mg x b)))

compCurryR :: Fun(k -> (a,b) -> d) -> Fun(a -> c -> b) -> Fun(k -> (a,c) -> d)
compCurryR (Fun ef f) (Fun eg g) = Fun (Lam P1 (PPair P2 P3) (Ap ef X1 (EPair X2 (Ap eg X2 X3)))) (\ x (a,b) -> f x(a,g a b))

nEgate:: Fun(k -> v -> Bool) -> Fun(k -> v -> Bool)
nEgate (Fun ef f) = Fun (Lam P1 P2 (Neg (Ap ef X1 X2))) (\ x y -> not(f x y))

always:: Fun(a -> b -> Bool)
always = constant True

both:: Fun(a -> b -> Bool) -> Fun(a -> b -> Bool) -> Fun(a -> b -> Bool)
both (Fun ef e) (Fun ff f) = Fun (Lam P1 P2 (Ap Both (Ap ef X1 X2) (Ap ff X1 X2)))  (\ a b -> (e a b) && (f a b))

lift :: (a -> b -> c) -> Fun (a -> b -> c)  -- This is used in the tests, not good to use it elsewhere.
lift f = Fun (Lift f) f



-- ============================================================================================
-- | Given a BaseRep we can materialize a (Collect k v) into the type witnessed by the BaseRep.
-- Recall a (Collect k v) has no intrinsic type (it is just an ABSTRACT sequence of tuples), so
-- the witness describes how to turn them into the chosen datatype.
-- =============================================================================================

materialize :: (Ord k) => BaseRep f k v -> Collect (k,v) -> f k v
materialize ListR x = List (runCollect x [] (:))
materialize MapR x = runCollect x Map.empty (\ (k,v) ans -> Map.insert k v ans)
materialize SetR x = Sett (runCollect x Set.empty (\ (k,_) ans -> Set.insert k ans))
materialize BiMapR x = runCollect x  biMapEmpty (\ (k,v) ans -> addpair k v ans)
materialize SingleR x = runCollect x Fail (\ (k,v) _ignore -> Single k v)
-- materialize other x = error ("Can't materialize compound (Iter f) type: "++show other++". Choose some other BaseRep.")


-- ================================================================================
-- On the flip side, a witness can be used to specifiy how to build a datatype from
-- a CONCRETE sequence of tuples (a list). A way to import a type from from a list.
-- ================================================================================

addp :: (Ord k,Basic f) => (k,v) -> f k v -> f k v
addp (k,v) xs = addpair k v xs

fromList:: Ord k => BaseRep f k v -> [(k,v)] -> f k v
fromList MapR xs = foldr addp Map.empty xs
fromList ListR xs = List (sortBy (\ x y -> compare (fst x) (fst y)) xs)
fromList SetR xs = foldr addp (Sett (Set.empty)) xs
fromList BiMapR xs = biMapFromList xs
fromList SingleR xs = foldr addp Fail xs
-- fromList other xs = error ("No fromList for compound iterators")


-- =========================================================================================
-- Now we make an iterator that collects triples, on the intersection
-- of the domain of the two Iter types 'f' and 'g'. An answer of (k,b,c) means that
-- (k,b) is in m::f k a, and (k,c) is in n::g k c. All the other possible triples
-- are skipped over.  This is an instance of a thing called a "Generic Join"
-- See https://arxiv.org/pdf/1310.3314.pdf  or  http://personales.dcc.uchile.cl/~pbarcelo/ngo.pdf
-- The number of tuples it touches is proportional to the size of the output (modulo log factors).
-- It's cost is unrelated to the size of its inputs (modulo log factors)
-- This is a very specific version of the AndD compound iterator. It is used in the function 'eval'
-- =========================================================================================

(⨝) ::  (Ord k,Iter f,Iter g) =>  f k b -> g k c -> Collect (k,b,c)
(⨝) = domEq

domEq:: (Ord k,Iter f,Iter g) =>  f k b -> g k c -> Collect (k,b,c)
domEq m n = do
    triplem <- nxt m
    triplen <- nxt n
    let loop (mt@(k1,b,nextm)) (nt@(k2,c,nextn)) =
          case compare k1 k2 of
            EQ -> front (k1,b,c) (domEq nextm nextn)
            LT -> do { mt' <- lub k2 nextm; loop mt' nt }
            GT -> do { nt' <- lub k1 nextn; loop mt nt' }
    loop triplem triplen

-- This is included here for the benchmark tests. It is much slower because it does not use lub.

domEqSlow:: (Ord k,Iter f, Iter g) =>  f k b -> g k c -> Collect (k,b,c)
domEqSlow m n = do
    triplem <- nxt m
    triplen <- nxt n
    let loop (mt@(k1,b,nextm)) (nt@(k2,c,nextn)) =
          case compare k1 k2 of
            EQ -> front (k1,b,c) (domEqSlow nextm nextn)
            LT -> do { mt' <- nxt nextm; loop mt' nt }
            GT -> do { nt' <- nxt nextn; loop mt nt' }
    loop triplem triplen


-- =================================================================================
-- Query is a single datatype that incorporates a language that describes how to build
-- compound iterators, from other iterators.
-- =================================================================================

data Query k v where
   BaseD :: (Iter f,Ord k) => BaseRep f k v -> f k v -> Query k v
   ProjectD :: Ord k => Query k v -> Fun (k -> v -> u) -> Query k u
   AndD :: Ord k => Query k v -> Query k w -> Query k (v,w)
   ChainD:: (Ord k,Ord v) => Query k v -> Query v w -> Fun(k -> (v,w) -> u) -> Query k u
   AndPD::  Ord k => Query k v -> Query k u -> Fun(k -> (v,u) -> w) -> Query k w
   OrD:: Ord k => Query k v -> Query k v -> Fun(v -> v -> v) -> Query k v
   GuardD:: Ord k => Query k v -> Fun (k -> v -> Bool) -> Query k v
   DiffD :: Ord k => Query k v -> Query k u -> Query k v

-- ======================================================================================
-- smart constructors for Query. These apply semantic preserving rewrites when applicable
-- ======================================================================================

smart :: Bool
smart = True  -- for debugging purposes, this can be set to False, in which case no rewrites occurr.

projD ::  Ord k => Query k v -> Fun (k -> v -> u) -> Query k u
projD x y = case (x,y) of
   (ProjectD f p, q) | smart -> projD f (compose1 q p)
   (AndD f g,q) | smart -> andPD f g (compose1 q second)
   (AndPD f g p, q) | smart -> andPD f g (compose1 q p)
   (f, p) -> ProjectD f p

andD :: Ord k => Query k v1 -> Query k v2 -> Query k (v1, v2)
andD (ProjectD f p) g | smart = AndPD f g (compSndL second p)
andD f (ProjectD g p) | smart = AndPD f g (compSndR second p)
andD f g = AndD f g

andPD :: Ord k => Query k v1 -> Query k u -> Fun (k -> (v1, u) -> v) -> Query k v
andPD (ProjectD f p) g q | smart = andPD f g (compSndL q p)
andPD f g p = AndPD f g p

chainD :: (Ord k,Ord v) => Query k v -> Query v w -> Fun (k -> (v, w) -> u) -> Query k u
chainD f (ProjectD g p) q | smart = chainD f g (compCurryR q p)
chainD f g p = ChainD f g p

guardD :: Ord k => Query k v -> Fun (k -> v -> Bool) -> Query k v
guardD (GuardD q1 test1) test2 | smart = GuardD q1 (both test1 test2)
guardD qry test = GuardD qry test



-- ================================================================================
-- | Compile the (Exp (f k v)) to a Query iterator, and a BaseRep that indicates
--   how to materialize the iterator to the correct type. Recall the iterator
--   can be used to constuct many things using runCollect, but here we want
--   to materialize it to the same type as the (Exp (f k v)), i.e. (f k v).
-- ================================================================================

compile:: Exp (f k v) -> (Query k v,BaseRep f k v)
compile (Base rep relation) = (BaseD rep relation,rep)
compile (Singleton d r) = (BaseD SingleR (Single d r),SingleR)
compile (SetSingleton d  ) = (BaseD SingleR (SetSingle d  ),SingleR)
compile (Dom (Base SetR rel)) = (BaseD SetR rel,SetR)
compile (Dom (Singleton k v)) = (BaseD SetR (Sett(Set.singleton k)),SetR)
compile (Dom (SetSingleton k)) = (BaseD SetR (Sett(Set.singleton k)),SetR)
compile (Dom x) = (projD (fst(compile x)) (constant ()),SetR)
compile (Rng (Base SetR rel))  = (BaseD SetR (Sett(Set.singleton ())),SetR)
compile (Rng (Singleton k v))  = (BaseD SetR (Sett(Set.singleton v)),SetR)
compile (Rng (SetSingleton k)) = (BaseD SetR (Sett(Set.singleton ())),SetR)
compile (Rng f) = (BaseD SetR (rngStep (fst(compile f))),SetR)  -- We really ought to memoize this. It might be computed many times.
compile (DRestrict set rel) = (projD (andD (fst(compile set)) reld) rngSnd,rep)
    where (reld,rep) = compile rel
compile (DExclude set rel) = (DiffD reld (fst(compile set)),rep)
       where (reld,rep) = compile rel
compile (RRestrict rel set) =
   case (compile rel,compile set) of
      ((reld,rep),(BaseD _ x,_)) -> (GuardD reld (rngElem x),rep)
      ((reld,rep),(setd,_)) -> (chainD reld setd rngFst,rep)
compile (RExclude rel set) =
   case (compile rel,compile set) of
      ((reld,rep),(BaseD _ x,_)) -> (GuardD reld (nEgate (rngElem x)),rep)
      ((reld,rep),_) -> (GuardD reld (nEgate (rngElem (compute set))),rep)  -- This could be expensive
compile (UnionOverrideLeft rel1 rel2) =  (OrD rel1d (fst(compile rel2)) second,rep)   -- second uses value from rel2 to override value from rel1
    where (rel1d,rep) = compile rel1
compile (UnionOverrideRight rel1 rel2) =  (OrD rel1d (fst(compile rel2)) first,rep)   -- first uses value from rel1 to override value from rel2
    where (rel1d,rep) = compile rel1
compile (UnionPlus rel1 rel2) =  (OrD rel1d (fst(compile rel2)) plus,rep)
    where (rel1d,rep) = compile rel1
compile (Intersect rel1 rel2) = (andPD (fst(compile rel1)) (fst(compile rel2)) (constant ()) ,SetR)

-- ===========================================================================
-- run materializes compiled code, only if it is not already data
-- ===========================================================================

run :: Ord k => (Query k v,BaseRep f k v) -> f k v
run (BaseD SetR x,SetR) = x               -- If it is already data (BaseD)
run (BaseD MapR x,MapR) = x               -- and in the right form (the BaseRep's match)
run (BaseD SingleR x,SingleR) = x         -- just return the data
run (BaseD BiMapR x,BiMapR) = x           -- only need to materialize data
run (BaseD ListR x,ListR) = x             -- if the forms do not match.
run (BaseD source x,target) = materialize target (fifo x)      -- use fifo, since for, at least List, the order matters.
run (other,target) = materialize target (fifo other)           -- If it is a compund Iterator, than materialize it.

-- ==============================================================================================
-- Evaluate an (Exp t) into real data of type t. Try domain and type specific algorithms first,
-- and if those fail. Compile the formula as an iterator, then run the iterator to get an answer.
-- Here are some sample of the type specific algorithms we incorporate
--  x  ∈ (dom y)            haskey
--  x  ∉ (dom y)            not . haskey
-- x ∪ (singleton y)        addpair
-- (Set.singleton x) ⋪ y    removekey
-- x ⋫ (Set.singleton y)    easy on Bimap  remove val
-- (dom x) ⊆ (dom y)
-- ===============================================================================================

compute:: Exp t -> t
compute (Base rep relation) = relation

compute (Dom (Base SetR rel)) = rel
compute (Dom (Singleton k v)) = Sett (Set.singleton k)
compute (Dom (SetSingleton k)) = Sett (Set.singleton k)
compute (e@(Dom _)) = run(compile e)

compute (Rng (Base SetR rel)) = Sett (Set.singleton ())
compute (Rng (Singleton k v)) = Sett (Set.singleton v)
compute (Rng (SetSingleton k)) = Sett (Set.singleton ())
compute (e@(Rng _ )) = run(compile e)


compute (DRestrict (Base SetR (Sett set)) (Base MapR m)) = Map.restrictKeys m set
compute (DRestrict (SetSingleton k) (Base MapR m)) = Map.restrictKeys m (Set.singleton k)
compute (DRestrict (Singleton k v) (Base MapR m)) = Map.restrictKeys m (Set.singleton k)
compute (DRestrict (Base SetR (Sett s1)) (Base SetR (Sett s2))) = Sett(Set.intersection s1 s2)
compute (DRestrict (Base SetR x1) (Base rep x2)) = materialize rep $ do { (x,y,z) <- x1 `domEq` x2; one (x,z) }
compute (DRestrict (Dom (Base _ x1)) (Base rep x2)) = materialize rep $ do { (x,y,z) <- x1 `domEq` x2; one (x,z) }
compute (DRestrict (SetSingleton k) (Base rep x2)) = materialize rep $  do { (x,y,z) <- (SetSingle k) `domEq` x2; one (x,z) }
compute (DRestrict (Dom (Singleton k _)) (Base rep x2)) = materialize rep $  do { (x,y,z) <- (SetSingle k) `domEq` x2; one (x,z) }
compute (DRestrict (Rng (Singleton _ v)) (Base rep x2)) = materialize rep $  do { (x,y,z) <- (SetSingle v) `domEq` x2; one (x,z) }
  -- This case inspired by set expression in EpochBoundary.hs
compute (DRestrict (Dom (RRestrict (Base MapR delegs) (SetSingleton hk))) (Base MapR state)) =
   materialize MapR (do { (x,y,z) <- delegs `domEq` state; when (not (y==hk)); one(x,z) })
compute (e@(DRestrict _ _ )) = run(compile e)

compute (DExclude (SetSingleton n) (Base MapR m)) = Map.withoutKeys m (Set.singleton n)
compute (DExclude (Dom (Singleton n v)) (Base MapR m)) = Map.withoutKeys m (Set.singleton n)
compute (DExclude (Rng (Singleton n v)) (Base MapR m)) = Map.withoutKeys m (Set.singleton v)
compute (DExclude (Base SetR (Sett x1)) (Base MapR x2)) =  Map.withoutKeys x2 x1
compute (DExclude (Dom (Base MapR x1)) (Base MapR x2)) = noKeys x2 x1
compute (DExclude (SetSingleton k) (Base BiMapR x)) = removekey k x
compute (DExclude (Dom (Singleton k _)) (Base BiMapR x)) = removekey k x
compute (DExclude (Rng (Singleton _ v)) (Base BiMapR x)) = removekey v x
compute (e@(DExclude _ _ )) = run(compile e)

compute (RExclude (Base BiMapR x) (SetSingleton k)) = removeval k x
compute (RExclude (Base BiMapR x) (Dom (Singleton k v))) = removeval k x
compute (RExclude (Base BiMapR x) (Rng (Singleton k v))) = removeval v x
compute (RExclude (Base rep lhs) y) =
   materialize rep $ do { (a,b) <- lifo lhs; (c,_) <- lifo rhs; when (not(b==c)); one (a,b)} where rhs = compute y
compute (e@(RExclude _ _ )) = run(compile e)

compute (RRestrict (DRestrict (Dom (Base r1 stkcreds)) (Base r2 delegs)) (Dom (Base r3 stpools))) =
   materialize r2 $ do { (x,z,y) <- stkcreds `domEq` delegs; y `element` stpools; one (x,y)}
compute (e@(RRestrict _ _ )) = run(compile e)

compute (Elem k (Dom (Base rep x))) = haskey k x
compute (Elem k (Base rep rel)) = haskey k rel
compute (Elem k (Dom (Singleton key v))) = k==key
compute (Elem k (Rng (Singleton _ key))) = k==key
compute (Elem k (SetSingleton key)) = k==key
compute (Elem k set) = haskey k (compute set)

compute (NotElem k (Dom (Base rep x))) = not $ haskey k x
compute (NotElem k (Base rep rel)) = not $ haskey k rel
compute (NotElem k (Dom (Singleton key v))) = not $ k==key
compute (NotElem k (Rng (Singleton _ key))) = not $ k==key
compute (NotElem k (SetSingleton key)) = not $ k==key
compute (NotElem k set) = not $ haskey k (compute set)

compute (Subset (Base SetR (Sett x)) (Base SetR (Sett y))) = Set.isSubsetOf x y
compute (Subset (Base SetR (Sett x)) (Base MapR y)) = all (`Map.member` y) x
compute (Subset (Base MapR x) (Base MapR y)) = Map.foldrWithKey accum True x
   where accum k a ans = Map.member k y && ans
compute (Subset x y) = runCollect (lifo left) True (\ (k,v) ans -> haskey k right && ans)
  where left = (fst(compile x))
        right = (fst(compile y))

compute (Intersect (Base SetR (Sett x)) (Base SetR (Sett y))) = Sett (Set.intersection x y)
compute (Intersect (Base MapR x) (Base MapR y)) = Sett (Map.keysSet(Map.intersection x y))
compute (e@(Intersect a b)) = run(compile e)

compute (UnionOverrideLeft (Base rep x) (Singleton k v)) = addkv (k,v) x (\ l r -> r)   -- The value on the left is overwritten by the value on the right.
compute (e@(UnionOverrideLeft a b)) = run(compile e)

compute (UnionOverrideRight (Base rep x) (Singleton k v)) = addkv (k,v) x (\ l r -> l)  -- The value on the right is overwritten by the value on the left.
compute (e@(UnionOverrideRight a b)) = run(compile e)

compute (UnionPlus (Base MapR x) (Base MapR y)) = Map.unionWith (+) x y
compute (e@(UnionPlus a b)) = run(compile e)

compute (Singleton k v) = Single k v
compute (SetSingleton k) = (SetSingle k)


eval :: Embed s t => Exp t -> s
eval x = fromBase (compute x)

-- ==============================================================================================
-- To make compound iterators, i.e. instance (Iter Query), we need "step" functions for each kind
-- ==============================================================================================

-- ==== Project ====
projStep
  :: Ord k =>
     (t -> Collect (k, v, Query k v))
     -> Fun (k -> v -> u) -> t -> Collect (k, u, Query k u)
projStep next p f = do { (k,v,f') <- next f; one (k,apply p k v,ProjectD f' p) }

-- ===== And = ====
andStep
  :: Ord a =>
     (a, b1, Query a b1)
     -> (a, b2, Query a b2) -> Collect (a, (b1, b2), Query a (b1, b2))
andStep (ftrip@(k1,v1,f1)) (gtrip@(k2,v2,g2)) =
   case compare k1 k2 of
      EQ -> one (k1,(v1,v2), AndD f1 g2)
      LT -> do { ftrip' <- lubQuery k2 f1; andStep ftrip' gtrip  }
      GT -> do { gtrip' <- lubQuery k1 g2; andStep ftrip gtrip' }

-- ==== Chain ====
chainStep
  :: (Ord b, Ord a) =>
     (a, b, Query a b)
     -> Query b w -> Fun (a -> (b, w) -> u) -> Collect (a, u, Query a u)
chainStep (f@(d,r1,f1)) g comb = do
   (r2,w,g1) <- lubQuery r1 g
   case compare r1 r2 of
      EQ -> one (d,apply comb d (r2,w),ChainD f1 g comb)
      LT -> do { trip <- nxtQuery f1; chainStep trip g comb}
      GT -> error ("lub makes this unreachable")

-- ==== And with Projection ====
andPstep
  :: Ord a =>
     (a, b1, Query a b1)
     -> (a, b2, Query a b2)
     -> Fun (a -> (b1, b2) -> w)
     -> Collect (a, w, Query a w)
andPstep (ftrip@(k1,v1,f1)) (gtrip@(k2,v2,g2)) p =
   case compare k1 k2 of
      EQ -> one (k1,(apply p k1 (v1,v2)), AndPD f1 g2 p)
      LT -> do { ftrip' <- lubQuery k2 f1; andPstep ftrip' gtrip p }
      GT -> do { gtrip' <- lubQuery k1 g2; andPstep ftrip gtrip' p }

-- ==== Or with combine ====
orStep
  :: (Ord k, Ord a) =>
     (Query k v -> Collect (a, v, Query k v))
     -> Query k v
     -> Query k v
     -> Fun (v -> v -> v)
     -> Collect (a, v, Query k v)
orStep next f g comb =
   case (hasElem (next f), hasElem (next g)) of   -- We have to be careful, because if only one has a nxt, there is still an answer
      (Nothing,Nothing) -> none
      (Just(k1,v1,f1),Nothing) -> one (k1,v1,OrD f1 g comb)
      (Nothing,Just(k1,v1,g1)) -> one (k1,v1,OrD f g1 comb)
      (Just(k1,v1,f1),Just(k2,v2,g2)) ->
        case compare k1 k2 of
           EQ -> one (k1,apply comb v1 v2,OrD f1 g2 comb)
           LT -> one (k1,v1,OrD f1 g comb)
           GT -> one (k2,v2,OrD f g2 comb)

-- ===== Guard =====
guardStep
  :: Ord a =>
     (Query a b -> Collect (a, b, Query a b))
     -> Fun (a -> b -> Bool) -> Query a b -> Collect (a, b, Query a b)
guardStep next p f = do { triple <- next f; loop triple }
   where loop (k,v,f') = if (apply p k v) then one (k,v,GuardD f' p) else do { triple <- nxtQuery f'; loop triple}

-- ===== Difference by key =====
diffStep :: Ord k => (k, v, Query k v) -> Query k u -> Collect (k, v, Query k v)
diffStep (t1@(k1,u1,f1)) g =
   case hasElem (lubQuery k1 g) of
      Nothing -> one (k1,u1,DiffD f1 g)  -- g has nothing to subtract
      Just (t2@(k2,u2,g2)) -> case compare k1 k2 of
          EQ -> do { tup <- nxtQuery f1; diffStep tup g2 }
          LT -> one (k1,u1,DiffD f1 g)
          GT -> one (k1,u1,DiffD f1 g)   -- the hasLub guarantees k1 <= k2, so this case is dead code

-- ========== Rng ====================
rngStep :: Ord v => Query k v -> Sett v ()
rngStep dat = materialize SetR (loop dat)
  where loop x = do { (k,v,x2) <- nxt x; front (v,()) (loop x2) }

-- =========================== Now the Iter instance for Query ======================

nxtQuery :: Query a b -> Collect (a, b, Query a b)
nxtQuery (BaseD rep x) = do {(k,v,x2) <- nxt x; one(k,v,BaseD rep x2)}
nxtQuery (ProjectD x p) = projStep nxtQuery p x
nxtQuery (AndD f g) = do { triple1 <- nxtQuery f; triple2 <- nxtQuery g; andStep triple1 triple2 }
nxtQuery (ChainD f g p) = do { trip <- nxtQuery f; chainStep trip g p}
nxtQuery (AndPD f g p) = do { triple1 <- nxtQuery f; triple2 <- nxtQuery g; andPstep triple1 triple2 p }
nxtQuery (OrD f g comb) = orStep nxtQuery f g comb
nxtQuery (GuardD f p) = guardStep nxtQuery p f
nxtQuery (DiffD f g) = do { trip <- nxtQuery f; diffStep trip g }

lubQuery :: Ord a => a ->  Query a b -> Collect (a, b, Query a b)
lubQuery key (BaseD rep x) = do {(k,v,x2) <- lub key x; one(k,v,BaseD rep x2)}
lubQuery key (ProjectD x p) = projStep (lubQuery key) p x
lubQuery key (AndD f g) = do { triple1 <- lubQuery key f; triple2 <- lubQuery key g; andStep triple1 triple2 }
lubQuery key (ChainD f g p) = do { trip <- lubQuery key f; chainStep trip g p}
lubQuery  key (AndPD f g p) = do { triple1 <- lubQuery key f; triple2 <- lubQuery key g; andPstep triple1 triple2 p}
lubQuery key (OrD f g comb) = orStep (lubQuery key) f g comb
lubQuery key (GuardD f p) = guardStep (lubQuery key) p f
lubQuery key (DiffD f g) = do { trip <- lubQuery key f; diffStep trip g}


instance Iter Query where
   nxt = nxtQuery
   lub = lubQuery

-- =======================================================================================
-- Finally we make smart constructors for Query, so we can lift un-embedded Base types
-- into Queries, so programmers don't need to know about List and Sett.

projectQ :: (Ord k, HasQuery c k v) => c -> Fun (k -> v -> u) -> Query k u
projectQ q fun = ProjectD (query q) fun

andQ :: (Ord k, HasQuery concrete1 k v, HasQuery concrete2 k w) => concrete1 -> concrete2 -> Query k (v, w)
andQ x y = AndD (query x) (query y)

orQ ::
  (Ord k, HasQuery concrete1 k v, HasQuery concrete2 k v) =>
  concrete1 -> concrete2 -> Fun (v -> v -> v) -> Query k v
orQ x y comb = OrD (query x) (query y) comb

chainQ ::
   (Ord k, Ord v, HasQuery concrete1 k v,HasQuery concrete2 v w) =>
   concrete1 -> concrete2 -> Fun (k -> (v, w) -> u) -> Query k u
chainQ x y p = ChainD (query x) (query y) p

andPQ ::
   (Ord k, HasQuery concrete1 k v, HasQuery concrete2 k u) =>
   concrete1 -> concrete2 -> Fun (k -> (v, u) -> w) -> Query k w
andPQ x y p = AndPD (query x) (query y) p

guardQ ::
   (Ord k, HasQuery concrete k v) =>
   concrete -> Fun (k -> v -> Bool) -> Query k v
guardQ x p = GuardD (query x) p

-- Don't know why this won't type check
-- diffQ :: (Ord k, HasQuery concrete1 k v, HasQuery concrete2 k u) => concrete1 -> concrete2 -> Query k v
-- diffQ = \ x y -> DiffD (query x) (query y)

class HasQuery concrete k v where
  query :: concrete -> Query k v

instance HasQuery (Query k v) k v where
   query xs = xs

instance Ord k => HasQuery [(k,v)] k v where
   query xs = BaseD ListR (List (sortBy (\ x y -> compare (fst x) (fst y)) xs))

instance Ord k => HasQuery (Set.Set k) k () where
   query xs = BaseD SetR (Sett xs)

instance Ord k => HasQuery (Map.Map k v) k v where
   query xs = BaseD MapR xs

instance (Ord v,Ord k) => HasQuery (BiMap v k v) k v where
   query xs = BaseD BiMapR xs

instance Ord k => HasQuery (Single k v) k v where
   query xs = BaseD SingleR xs

-- =================================================
-- Show Instances
-- =================================================

instance Show (BaseRep f k v) where
  show MapR = "Map"
  show SetR = "Set"
  show ListR = "List"
  show SingleR = "Single"
  show BiMapR = "BiMap"

instance Show (Exp t) where
  show (Base rep x) = show rep++"?"
  show (Dom x) = "(dom "++show x++")"
  show (Rng x) = "(rng "++show x++")"
  show (DRestrict x y) = "("++show x++" ◁ "++show y++")"
  show (DExclude x y) = "("++show x++" ⋪ "++show y++")"
  show (RRestrict x y) = "("++show x++" ▷ "++show y++")"
  show (RExclude x y) = "("++show x++" ⋫ "++show y++")"
  show (Elem k x) = "("++show k++" ∈ "++show x++")"
  show (NotElem k x) = "("++show k++" ∉ "++show x++")"
  show (Intersect x y) = "("++show x ++" ∩ "++show y++")"
  show (Subset x y) = "("++show x++" ⊆ "++show y++")"
  show (UnionOverrideLeft x y) = "("++show x++" ∪ "++show y++")"
  show (UnionPlus x y) = "("++show x++" ∪+ "++show y++")"
  show (UnionOverrideRight x y) = "("++show x++" ⨃ "++show y++")"
  show (Singleton x y) = "(singleton _ _ )"
  show (SetSingleton x) = "(setSingleton _ )"

ppQuery :: Query k v -> Doc
ppQuery (BaseD rep f) = parens $ text(show rep)
ppQuery (ProjectD f p) = parens $ text "Proj" <+> align(vsep[ppQuery f,text(show p)])
ppQuery (AndD f g) = parens $ text "And" <+> align(vsep[ppQuery f,ppQuery g])
ppQuery (ChainD f g p) = parens $ text "Chain" <+> align(vsep[ppQuery f,ppQuery g,text(show p)])
ppQuery (OrD f g p) = parens $ text "Or" <+> align(vsep[ppQuery f,ppQuery g,text(show p)])
ppQuery (GuardD f p) = parens $ text "Guard" <+> align(vsep[ppQuery f,text(show p)])
ppQuery (DiffD f g) = parens $ text "Diff" <+> align(vsep[ppQuery f,ppQuery g])
ppQuery (AndPD f g p) = parens $ text "AndP" <+> align(vsep[ppQuery f,ppQuery g,text(show p)])


instance Show (Query k v) where
   show x = show(ppQuery x)