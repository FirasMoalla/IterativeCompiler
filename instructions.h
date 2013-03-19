//These are the declarations of both the GCode type and the instruction type.
#ifndef INSTRUCTION_H
#define INSTRUCTION_H

typedef enum {       //Number of Arguments
         Unwind,     //0 
         PushGlobal, //1 
         PushInt,    //1
         Push,       //1
         MkAp,       //0
         Update,     //1
         Pop,        //1
         Slide,      //1
         Alloc,      //1
         Eval,       //0
         Add, Sub, Mul, Div, Neg, //0
         Eq, Ne, Lt, Le, Gt, Ge,  //0
         Pack,       //2
         CaseJump,   //1
         CaseAlt,    //1
         CaseAltEnd, //1
         Split,      //1
         Label,      //1
         FunDef,      //1
         Print,      //0
         Par         //0
} GCode;

typedef int codePtr;

struct _instruction {
    GCode type;
    union {
        char * pughGlobVal;
        char * caseJumpVal;
        char * caseAltVal;
        int pushIntVal;
        int pushVal;
        int updateVal;
        int popVal;
        int slideVal;
        int allocVal;
        int splitVal;
        struct {
            int arity;
            char *name;
        } funVals;
        struct {
            int tag, arity;
        } packVals;
    };

};
typedef struct _instruction instruction;

#endif