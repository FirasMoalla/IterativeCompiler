{-This file will contain all the code necessary for the basic GMachine
 -
 - the functions defined here or called from {Language, Parser, Heap}.hs
 - will enable us to define and call the following top-level function for
 - running programs:
 -
 - runProg :: [Char] -> [Char]
 - runProg = showResults . eval . compile . parse
 -}
import Language
import Parser
import Heap

--The state of the G-Machine will be stored in the following 5-tuple
type GMState = (GMCode,     --Current instuction stream
                GMStack,    --Current Stack
                GMHeap,     --The Heap holding the program graph
                GMGlobals,  --Addresses for globals in the heap
                GMStats)    --Statistics about the computation

--The code for the GMCode type and `setter and getter' functions are below.
type GMCode = [Instruction]

data Instruction = 
          Unwind 
        | PushGlobal Name
        | PushInt Int
        | Push Int
        | MkAp
        | Update Int
        | Pop Int
    deriving Eq

getCode :: GMState -> GMCode
getCode (code, _, _, _, _) = code

putCode :: GMCode -> GMState -> GMState
putCode code' (code, stack, heap, globals, stats) 
    = (code', stack, heap, globals, stats)


--The code for the GMStack is below:
type GMStack = [Addr]

getStack :: GMState -> GMStack
getStack (_, stack, _, _, _) = stack

putStack :: GMStack -> GMState -> GMState
putStack stack' (code, stack, heap, globals, stats) 
    = (code, stack', heap, globals, stats)

--The code for the state's heap:
type GMHeap = Heap Node

--A Node is either a number (a result), an application of two other nodes, or
--the arity & gCode sequence for when the global can be executed
data Node = 
          NNum Int
        | NAp Addr Addr
        | NGlobal Int GMCode
        | NInd Addr         --Indirection node
    deriving Eq


getHeap :: GMState -> GMHeap
getHeap (_, _, heap, _, _) = heap

putHeap :: GMHeap -> GMState -> GMState
putHeap heap' (code, stack, heap, globals, stats) 
    = (code, stack, heap', globals, stats)


--The code for GMGlobals is below. Because the globals of a program do not
--change during execution, a `put' function is not needed
type GMGlobals = Assoc Name Addr

getGlobals :: GMState -> GMGlobals
getGlobals (_, _, _, globals, _) = globals

putGlobals :: (Name, Addr) -> GMState -> GMState
putGlobals global' (c, s, h, globals, stats) 
        =  (c, s, h, global', stats)

--GMStats:
type GMStats = Int

statInitial :: GMStats
statInitial = 0

statIncSteps :: GMStats -> GMStats
statIncSteps s = s + 1

statGetSteps :: GMStats -> Int
statGetSteps s = s

getStats :: GMState -> GMStats
getStats (code, stack, heap, globals, stats) = stats

putStats :: GMStats -> GMState -> GMState
putStats stats' (code, stack, heap, globals, stats) = 
        (code, stack, heap, globals, stats')

--The Evaluator function takes a list of states (the first of which is created 
--by the compiler)
eval :: GMState -> [GMState]
eval state = state : restStates
        where
        restStates 
            | gmFinal state     = []
            | otherwise         = eval nextState
        nextState = doAdmin (step state)

--doAdmin allows for any between-state calculations that need to be made. In
--this case we increment the stats counter. 
doAdmin :: GMState -> GMState
doAdmin state = putStats (statIncSteps (getStats state)) state

--gmFinal state checks if there is any code left to execute; if there is not,
--we have reached the final state. 
gmFinal :: GMState -> Bool
gmFinal s = case (getCode s) of
                []        -> True
                otherwise -> False

step :: GMState -> GMState
step state = dispatch code (putCode rest state)
            where (code:rest) = getCode state

dispatch :: Instruction -> GMState -> GMState
dispatch (PushGlobal f) = pushglobal f
dispatch (PushInt n)    = pushint n
dispatch MkAp           = mkap
dispatch (Push n)       = push n
--dispatch (Slide n)      = slide n
dispatch (Pop n)        = popInst n
dispatch (Update n)     = update n
dispatch Unwind         = unwind

pushglobal :: Name -> GMState ->GMState
pushglobal f state 
    = putStack (a : getStack state) state
        where 
        a = aLookupString (getGlobals state) f (error ("Undeclared global " ++ f))

pushint :: Int -> GMState -> GMState
pushint n state = putStack (a : getStack state') state'
    where (a, state') = case lookupRes of  
                        Just ad -> (ad, state)
                        Nothing -> cleanUp (hAlloc (getHeap state) (NNum n)) 
          lookupRes = lookup (show n) (getGlobals state)
          cleanUp (heap', ad1) = (ad1, (putHeap heap' (putGlobals (show n, ad1)state)))

mkap :: GMState -> GMState
mkap state
    = putHeap heap' (putStack (a:as') state)
    where (heap', a) = hAlloc (getHeap state) (NAp a1 a2)
          (a1:a2:as') = getStack state

push :: Int -> GMState -> GMState
push n state
    = putStack (a:as) state
    where as = getStack state
          a  = getArg (hLookup (getHeap state) (as !! (n+1)))

getArg :: Node -> Addr
getArg (NAp a1 a2) = a2
getArg _ = error "Error in call to getArg: not an application node."

slide :: Int -> GMState -> GMState
slide n state
    = putStack (a: drop n as) state
    where (a:as) = getStack state

update :: Int -> GMState -> GmState
update n state
    = putStack (drop 1 (a:as)) (putHeap state


unwind :: GMState -> GMState
unwind state
    = newState (hLookup heap a)
    where
        (a:as) = getStack state
        heap   = getHeap state
        newState (NNum n) = state
        newState (NAp a1 a2) = putCode [Unwind] (putStack (a1:a:as) state)
        newState (NGlobal n c)
                | length as < n     = error "Unwinding with too few args"
                | otherwise         = putCode c state

--mapAccuml is a utility function that will be used frequently in the code to
--come.
mapAccuml :: (a -> b -> (a, c)) -> a -> [b] -> (a, [c])
mapAccuml f acc []      = (acc, [])
mapAccuml f acc (x:xs)  = (acc2, x':xs')
                where
                    (acc1, x')  = f acc x
                    (acc2, xs') = mapAccuml f acc1 xs


--Compile functions are broken into portions for compiling SC, R and C
compile :: CoreProgram -> GMState
compile prog = (initCode, [], heap, globals, statInitial)
        where (heap, globals) =  buildInitialHeap prog

--Once compiled a supercombinator for the G-Machine will be of the form:
type GMCompiledSC = (Name, Int, GMCode)

buildInitialHeap :: CoreProgram -> (GMHeap, GMGlobals)
buildInitialHeap prog = 
        mapAccuml allocateSC hInitial compiled
            where compiled = map compileSC prog

--allocating SCs in the heap makes sure that there is a new heap containing the
--new global representing the SC
allocateSC :: GMHeap -> GMCompiledSC -> (GMHeap, (Name, Addr))
allocateSC heap (name, numArgs, gmCode) = (newHeap, (name, addr))
        where
            (newHeap, addr) = hAlloc heap (NGlobal numArgs gmCode)

--The special-case supercombinator "main" is required of every program and is
--the first function to be called. So the initial gCode for every program will
--be loading that supercombinator
initCode :: GMCode
initCode = [PushGlobal "main", Unwind]

compileSC :: (Name, [Name], CoreExpr) -> GMCompiledSC
compileSC (name, env, body)
    = (name, length env, compileR body (zip env [0..]))

compileR :: GMCompiler
compileR expr env = compileC expr env ++ [Slide (length env + 1), Unwind]

compileC :: GMCompiler
compileC (EVar v) env
    | elem v (aDomain env)  = [Push n]
    | otherwise             = [PushGlobal v]
    where n = aLookupString env v (error "This error can't possibly happen")
compileC (ENum n) env       = [PushInt n]
compileC (EAp e1 e2) env    = compileC e2 env ++ 
                              compileC e1 (argOffset 1 env) ++ 
                              [MkAp]

type GMCompiler = CoreExpr -> GMEnvironment -> GMCode

type GMEnvironment = Assoc Name Int

argOffset :: Int -> GMEnvironment -> GMEnvironment
argOffset n env = [(v, n+m) | (v, m) <- env]

--In the Mark I GMachine there are no primitives, but we should still have them
--defined
compiledPrimitives :: [GMCompiledSC]
compiledPrimitives = []


{-The following are the printing functions needed for when viewing the results
 - of compilation in GHCI
 -}

showResults :: [GMState] -> String
showResults states
    = iDisplay (iConcat [IStr "Supercombinator definitions:", INewline
                        ,iInterleave INewline (map (showSC s) (getGlobals s))
                        ,INewline, INewline, IStr "State transitions:", INewline
                        ,INewline
                        ,iLayn (map showState states), INewline, INewline
                        ,showStats (last states)])
                where (s:ss) = states

showSC :: GMState -> (Name, Addr) -> Iseq
showSC state (name, addr)
    = iConcat [ IStr "Code for ", IStr name, INewline
               ,showInstructions code, INewline, INewline]
        where 
            (NGlobal arity code) = (hLookup (getHeap state) addr)

showInstructions :: GMCode -> Iseq
showInstructions code 
    = iConcat [IStr "  Code:{",
               IIndent (iInterleave INewline (map showInstruction code)),
               IStr "}", INewline]

--Functions to turn each instruction into an appropriate Iseq
showInstruction :: Instruction -> Iseq
showInstruction Unwind         = IStr "Unwind"
showInstruction (PushGlobal f) = (IStr "Pushglobal ") `IAppend` (IStr f)
showInstruction (Push n)       = (IStr "Push ") `IAppend` (iNum n)
showInstruction (PushInt n)    = (IStr "Pushint ") `IAppend` (iNum n)   
showInstruction MkAp           = IStr "MkAp"
showInstruction (Update n)     = (IStr "Update ") `IAppend` (iNum n)   
showInstruction (Pop n)        = (IStr "Pop ") `IAppend` (iNum n)   

--showState will take the GCode and the stack from a given state and 
--wrap them in Iseqs
showState :: GMState -> Iseq
showState state
    = iConcat [showStack state, INewline
              ,showInstructions (getCode state), INewline]

--When preparing the stack to be printed
showStack :: GMState -> Iseq
showStack state
    = iConcat [IStr " Stack:["
              ,IIndent (iInterleave INewline
                                    (map (showStackItem state)
                                         (reverse (getStack state))))
              ,IStr "]"]

showStackItem :: GMState -> Addr -> Iseq
showStackItem state addr
    = iConcat [IStr (showAddr addr), IStr ": "
              ,showNode state addr (hLookup (getHeap state) addr)]

showNode :: GMState -> Addr -> Node -> Iseq
showNode state addr (NNum n)         = iNum n 
showNode state addr (NAp ad1 ad2)    = iConcat [IStr "Ap ", IStr (showAddr ad1)
                                               ,IStr " ", IStr (showAddr ad2)]
showNode state addr (NGlobal n code) = iConcat [IStr "Global ", IStr v]
                    where v = head [n | (n, b) <- getGlobals state, addr == b]
showNode state addr (NInd ad1)  = iConcat [iStr "Indirection ", IStr (showAddr ad1)]

showStats :: GMState -> Iseq
showStats state = iConcat [IStr "Steps taken: "
                          ,iNum (statGetSteps (getStats state))]