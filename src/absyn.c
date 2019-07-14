#include "gwion_util.h"
#include "gwion_ast.h"

Var_Decl new_var_decl(MemPool p, struct Symbol_* xid, const Array_Sub array, const loc_t pos) {
  Var_Decl a = mp_calloc(p, Var_Decl);
  a->xid = xid;
  a->array = array;
  a->pos = pos;
  return a;
}

ANN static void free_var_decl(MemPool p, Var_Decl a) {
  if(a->array)
    free_array_sub(p, a->array);
  free_loc(p, a->pos);
  mp_free(p, Var_Decl, a);
}

void free_array_sub(MemPool p, Array_Sub a) {
  if(a->exp)
    free_exp(p, a->exp);
  mp_free(p, Array_Sub, a);
}

Var_Decl_List new_var_decl_list(MemPool p, const Var_Decl decl, const Var_Decl_List list) {
  Var_Decl_List a = mp_calloc(p, Var_Decl_List);
  a->self = decl;
  a->next = list;
  return a;
}

ANN static void free_var_decl_list(MemPool p, Var_Decl_List a) {
  if(a->next)
    free_var_decl_list(p, a->next);
  free_var_decl(p, a->self);
  mp_free(p, Var_Decl_List, a);
}

Type_Decl* new_type_decl(MemPool p, const ID_List xid) {
  Type_Decl* a = mp_calloc(p, Type_Decl);
  a->xid = xid;
  return a;
}

Type_Decl* new_type_decl2(MemPool p, const Exp exp) {
  Type_Decl* a = mp_calloc(p, Type_Decl);
  a->exp = exp;
  return a;
}

Array_Sub new_array_sub(MemPool p, const Exp exp) {
  Array_Sub a = mp_calloc(p, Array_Sub);
  a->exp = exp;
  a->depth = 1;
  return a;
}

Array_Sub prepend_array_sub(const Array_Sub a, const Exp exp) {
  if(exp) {
    exp->next = a->exp;
    a->exp = exp;
  }
  ++a->depth;
  return a;
}

Type_Decl* add_type_decl_array(Type_Decl* a, const Array_Sub array) {
  a->array = array;
  return a;
}

ANN static Exp new_exp(MemPool p, const ae_exp_t type, const loc_t pos) {
  Exp a = mp_calloc(p, Exp);
  a->exp_type = type;
  a->pos = pos;
  return a;
}

Exp new_exp_lambda(MemPool p, const Symbol xid, const Arg_List args, const Stmt code) {
  Exp a = new_exp(p, ae_exp_lambda, loc_cpy(p, code->pos));
  a->meta = ae_meta_var;
  a->d.exp_lambda.args = args;
  a->d.exp_lambda.code = code;
  a->d.exp_lambda.name = xid;
  return a;
}

ANN static void free_exp_lambda(MemPool p, Exp_Lambda* lambda) {
  if(lambda->args)
    free_arg_list(p, lambda->args);
  free_stmt(p, lambda->code);
  if(lambda->def) {
    free_loc(p, lambda->def->pos);
    mp_free(p, Func_Def, lambda->def);
  }
}

Exp new_exp_array(MemPool p, const Exp base, const Array_Sub array) {
  Exp a = new_exp(p, ae_exp_array, loc_cpy(p, base->pos));
  a->meta = ae_meta_var;
  a->d.exp_array.base = base;
  a->d.exp_array.array = array;
  return a;
}

ANN static void free_exp_array(MemPool p, Exp_Array* a) {
  free_array_sub(p, a->array);
  free_exp(p, a->base);
}

Exp new_exp_typeof(MemPool p, Exp exp) {
  Exp a = new_exp(p, ae_exp_typeof, loc_cpy(p, exp->pos));
  a->d.exp_typeof.exp = exp;
  return a;
}

ID_List new_id_list(MemPool p, struct Symbol_* xid, const loc_t pos) {
  ID_List a = mp_calloc(p, ID_List);
  a->xid = xid;
  a->pos = pos;
  return a;
}

ID_List prepend_id_list(MemPool p, struct Symbol_* xid, const ID_List list, const loc_t pos) {
  ID_List a = new_id_list(p, xid, pos);
  a->next = list;
  return a;
}

void free_id_list(MemPool p, ID_List a) {
  if(a->next)
    free_id_list(p, a->next);
  free_loc(p, a->pos);
  mp_free(p, ID_List, a);
}

void free_type_decl(MemPool p, Type_Decl* a) {
  if(a->types)
    free_type_list(p, a->types);
  if(a->array)
    free_array_sub(p, a->array);
  if(a->xid)
    free_id_list(p, a->xid);
  if(a->exp)
    free_exp(p, a->exp);
  mp_free(p, Type_Decl, a);
}

Exp new_exp_decl(MemPool p, Type_Decl* td, const Var_Decl_List list) {
  Exp a = new_exp(p, ae_exp_decl, loc_cpy(p, td_pos(td)));
  a->d.exp_decl.td = td;
  a->d.exp_decl.list = list;
  return a;
}

ANN static void free_exp_decl(MemPool p, Exp_Decl* a) {
  free_type_decl(p, a->td);
  free_var_decl_list(p, a->list);
}

Exp new_exp_binary(MemPool p, const Exp lhs, const Symbol op, const Exp rhs) {
  Exp a = new_exp(p, ae_exp_binary, loc_cpy(p, lhs->pos));
  a->meta = ae_meta_value;
  a->d.exp_binary.lhs = lhs;
  a->d.exp_binary.op = op;
  a->d.exp_binary.rhs = rhs;
  return a;
}

ANN static void free_exp_binary(MemPool p, Exp_Binary* binary) {
  free_exp(p, binary->lhs);
  free_exp(p, binary->rhs);
}

Exp new_exp_cast(MemPool p, Type_Decl* td, const Exp exp) {
  Exp a = new_exp(p, ae_exp_cast, loc_cpy(p, exp->pos));
  a->meta = ae_meta_value;
  a->d.exp_cast.td = td;
  a->d.exp_cast.exp = exp;
  return a;
}

ANN static void free_exp_cast(MemPool p, Exp_Cast* a) {
  free_type_decl(p, a->td);
  free_exp(p, a->exp);
}

Exp new_exp_post(MemPool p, const Exp exp, const Symbol op) {
  Exp a = new_exp(p, ae_exp_post, loc_cpy(p, exp->pos));
  a->meta = ae_meta_var;
  a->d.exp_post.exp = exp;
  a->d.exp_post.op = op;
  return a;
}

ANN static inline void free_exp_post(MemPool p, Exp_Postfix* post) {
  free_exp(p, post->exp);
}

static Exp new_exp_prim(MemPool p, const loc_t pos) {
  Exp a = new_exp(p, ae_exp_primary, pos);
  a->meta = ae_meta_value;
  return a;
}

Exp new_exp_prim_int(MemPool p, const unsigned long i, const loc_t pos) {
  Exp a = new_exp_prim(p, pos);
  a->d.exp_primary.primary_type = ae_primary_num;
  a->d.exp_primary.d.num = i;
  return a;
}

Exp new_exp_prim_float(MemPool p, const m_float num, const loc_t pos) {
  Exp a = new_exp_prim(p, pos);
  a->d.exp_primary.primary_type = ae_primary_float;
  a->d.exp_primary.d.fnum = num;
  return a;
}

Exp new_exp_prim_string(MemPool p, const m_str s, const loc_t pos) {
  Exp a = new_exp_prim(p, pos);
  a->d.exp_primary.primary_type = ae_primary_str;
  a->d.exp_primary.d.str = s;
  return a;
}

Exp new_exp_prim_nil(MemPool p, const loc_t pos) {
  Exp a = new_exp_prim(p, pos);
  a->d.exp_primary.primary_type = ae_primary_nil;
  return a;
}

Exp new_exp_prim_id(MemPool p, struct Symbol_* xid, const loc_t pos) {
  Exp a = new_exp_prim(p, pos);
  a->meta = ae_meta_var;
  a->d.exp_primary.primary_type = ae_primary_id;
  a->d.exp_primary.d.var = xid;
  return a;
}

Exp new_exp_prim_hack(MemPool p, const Exp exp) {
  Exp a = new_exp_prim(p, loc_cpy(p, exp->pos));
  a->d.exp_primary.primary_type = ae_primary_hack;
  a->d.exp_primary.d.exp = exp;
  return a;
}

Exp new_exp_prim_char(MemPool p, const m_str chr, const loc_t pos) {
  Exp a = new_exp_prim(p, pos);
  a->d.exp_primary.primary_type = ae_primary_char;
  a->d.exp_primary.d.chr = chr;
  return a;
}

Exp new_exp_prim_array(MemPool p, const Array_Sub exp, const loc_t pos) {
  Exp a = new_exp_prim(p, pos);
  a->d.exp_primary.primary_type = ae_primary_array;
  a->d.exp_primary.d.array = exp;
  return a;
}

Exp new_exp_prim_vec(MemPool p, const ae_prim_t t, Exp e) {
  Exp a = new_exp_prim(p, loc_cpy(p, e->pos));
  a->d.exp_primary.primary_type = t;
  a->d.exp_primary.d.vec.exp = e;
  do ++a->d.exp_primary.d.vec.dim;
  while((e = e->next));
  return a;
}

static inline Exp new_exp_unary_base(MemPool p, const Symbol oper, const loc_t pos)  {
  Exp a = new_exp(p, ae_exp_unary, pos);
  a->d.exp_unary.op = oper;
  return a;
}

Exp new_exp_unary(MemPool p, const Symbol oper, const Exp exp) {
  Exp a = new_exp_unary_base(p, oper, loc_cpy(p, exp->pos));
  a->meta = exp->meta;
  a->d.exp_unary.exp = exp;
  return a;
}

Exp new_exp_unary2(MemPool p, const Symbol oper, Type_Decl* td) {
  Exp a = new_exp_unary_base(p, oper, loc_cpy(p, td_pos(td)));
  a->meta = ae_meta_value;
  a->d.exp_unary.td = td;
  return a;
}

Exp new_exp_unary3(MemPool p, const Symbol oper, const Stmt code) {
  Exp a = new_exp_unary_base(p, oper, loc_cpy(p, code->pos));
  a->meta = ae_meta_value;
  a->d.exp_unary.code = code;
  return a;
}

ANN static void free_exp_unary(MemPool p, Exp_Unary* a) {
  if(a->exp)
    free_exp(p, a->exp);
  if(a->td)
    free_type_decl(p, a->td);
  if(a->code)
    free_stmt(p, a->code);
}

Exp new_exp_if(MemPool p, const restrict Exp cond, const restrict Exp if_exp, const restrict Exp else_exp) {
  Exp a = new_exp(p, ae_exp_if, loc_cpy(p, cond->pos));
  a->meta = ((!(if_exp ?: cond)->meta == ae_meta_var &&
              else_exp->meta == ae_meta_var) ? ae_meta_var : ae_meta_value);
  a->d.exp_if.cond = cond;
  a->d.exp_if.if_exp = if_exp;
  a->d.exp_if.else_exp = else_exp;
  return a;
}

ANN static void free_exp_if(MemPool p, Exp_If* a) {
  free_exp(p, a->cond);
  if(a->if_exp)
    free_exp(p, a->if_exp);
  free_exp(p, a->else_exp);
}

Tmpl* new_tmpl(MemPool p, const ID_List list, const m_int base) {
  Tmpl* a = mp_calloc(p, Tmpl);
  a->list = list;
  a->base = base;
  return a;
}

void free_tmpl(MemPool p, Tmpl* a) {
  if(a->base == -1)
    free_id_list(p, a->list);
  mp_free(p, Tmpl, a);
}

m_bool tmpl_base(const Tmpl* a) {
  if(a && a->base == -1)
    return GW_OK;
  return 0;
}

Func_Def new_func_def(MemPool p, struct Func_Base_ *base,const Stmt code,
    const ae_flag flag, const loc_t pos) {
  Func_Def a = mp_calloc(p, Func_Def);
  a->base = base;
  a->d.code = code;
  a->flag = flag;
  a->pos = pos;
  return a;
}

ANN m_bool compat_func(const restrict Func_Def lhs, const restrict Func_Def rhs) {
  Arg_List e1 = lhs->base->args;
  Arg_List e2 = rhs->base->args;

  while(e1 && e2) {
    if(e1->type != e2->type)
      return GW_ERROR;
    e1 = e1->next;
    e2 = e2->next;
  }
  if(e1 || e2)
    return GW_ERROR;
  return GW_OK;
}

ANN /* static */void free_func_base(MemPool p, struct Func_Base_ * a) {
  if(!a->func) {
    if(a->args)
      free_arg_list(p, a->args);
    free_type_decl(p, a->td);
  }
}

void free_func_def(MemPool p, Func_Def a) {
  if(!a->base->tmpl && !GET_FLAG(a, global)) {
    free_func_base(p, a->base);
    free_stmt(p, a->d.code);
    free_loc(p, a->pos);
    mp_free(p, Func_Def, a);
  }
}

struct Func_Base_* new_func_base(MemPool p, Type_Decl* td, const Symbol xid, const Arg_List args) {
  struct Func_Base_ *a = (struct Func_Base_*)mp_calloc(p, Func_Base);
  a->td = td;
  a->xid = xid;
  a->args = args;
  return a;
}

Stmt new_stmt_fptr(MemPool p, struct Func_Base_ *base, const ae_flag flag) {
  Stmt a              = new_stmt(p, ae_stmt_fptr, loc_cpy(p, td_pos(base->td)));
  a->d.stmt_fptr.base = base;
  base->td->flag |= flag;
  return a;
}

Stmt new_stmt_type(MemPool p, Type_Decl* ext, struct Symbol_ *xid) {
  Stmt a             = new_stmt(p, ae_stmt_type, loc_cpy(p, td_pos(ext)));
  a->d.stmt_type.ext = ext;
  a->d.stmt_type.xid = xid;
  return a;
}

ANN static void free_stmt_type(MemPool p, Stmt_Type a){
  if(!a->type)
    free_type_decl(p, a->ext);
}

ANN static void free_stmt_fptr(MemPool p, Stmt_Fptr a) {
  free_func_base(p, a->base);
}

Tmpl* new_tmpl_call(MemPool p, const Type_List tl) {
  Tmpl* a = mp_calloc(p, Tmpl);
  a->call = tl;
  return a;
}

ANN static void free_tmpl_call(MemPool p, Tmpl* a) {
  free_type_list(p, a->call);
  mp_free(p, Tmpl, a);
}

Exp new_exp_call(MemPool p, const Exp base, const Exp args) {
  Exp a = new_exp(p, ae_exp_call, loc_cpy(p, base->pos));
  a->meta = ae_meta_value;
  a->d.exp_call.func = base;
  a->d.exp_call.args = args;
  return a;
}

ANN static void free_exp_call(MemPool p, Exp_Call* a) {
  if(a->tmpl)
    free_tmpl_call(p, a->tmpl);
  free_exp(p, a->func);
  if(a->args)
    free_exp(p, a->args);
}

Exp new_exp_dot(MemPool p, const Exp base, struct Symbol_* xid) {
  Exp a = new_exp(p, ae_exp_dot, loc_cpy(p, base->pos));
  a->meta = ae_meta_var;
  a->d.exp_dot.base = base;
  a->d.exp_dot.xid = xid;
  return a;
}

ANN static void free_exp_dot(MemPool p, Exp_Dot* dot) {
  if(dot->base)
    free_exp(p, dot->base);
}

Exp prepend_exp(const restrict Exp exp, const restrict Exp next) {
  exp->next = next;
  return exp;
}

ANN static void free_exp_primary(MemPool p, Exp_Primary* a) {
  const ae_prim_t t = a->primary_type;
  if(t == ae_primary_hack)
    free_exp(p, a->d.exp);
  else if(t == ae_primary_array)
    free_array_sub(p, a->d.array);
  else if(t== ae_primary_complex ||
          t == ae_primary_polar  ||
          t == ae_primary_vec)
    free_exp(p, a->d.vec.exp);
}

ANN static void free_exp_typeof(MemPool p, Exp_Typeof* a) {
  free_exp(p, a->exp);
}

typedef void (*_exp_func)(MemPool, const union exp_data *);
static const _exp_func exp_func[] = {
  (_exp_func)free_exp_decl,    (_exp_func)free_exp_binary, (_exp_func)free_exp_unary,
  (_exp_func)free_exp_primary, (_exp_func)free_exp_cast,   (_exp_func)free_exp_post,
  (_exp_func)free_exp_call,    (_exp_func)free_exp_array,  (_exp_func)free_exp_if,
  (_exp_func)free_exp_dot,     (_exp_func)free_exp_lambda, (_exp_func)free_exp_typeof
};

void free_exp(MemPool p, Exp exp) {
  if(exp->next)
    free_exp(p, exp->next);
  exp_func[exp->exp_type](p, &exp->d);
  free_loc(p, exp->pos);
  mp_free(p, Exp, exp);
}

Arg_List new_arg_list(MemPool p, Type_Decl* td, const Var_Decl var_decl, const Arg_List arg_list) {
  Arg_List a = mp_calloc(p, Arg_List);
  a->td       = td;
  a->var_decl = var_decl;
  a->next     = arg_list;
  return a;
}

void free_arg_list(MemPool p, Arg_List a) {
  if(a->next)
    free_arg_list(p, a->next);
  if(a->td)
    free_type_decl(p, a->td);
  free_var_decl(p, a->var_decl);
  mp_free(p, Arg_List, a);

}

Stmt new_stmt_exp(MemPool p, const ae_stmt_t type, const Exp exp) {
  Stmt a = new_stmt(p, type, loc_cpy(p, exp->pos));
  a->d.stmt_exp.val = exp;
  return a;
}

Stmt new_stmt_code(MemPool p, const Stmt_List list) {
  Stmt a = new_stmt(p, ae_stmt_code, loc_cpy(p, list->stmt->pos));
  a->d.stmt_code.stmt_list = list;
  return a;
}

ANN static void free_stmt_code(MemPool p, Stmt_Code a) {
  if(a->stmt_list)
    free_stmt_list(p, a->stmt_list);
}

ANN static inline void free_stmt_exp(MemPool p, struct Stmt_Exp_* a) {
  if(a->val)
    free_exp(p, a->val);
}

Stmt new_stmt(MemPool p, const ae_stmt_t type, const loc_t pos) {
  Stmt a = mp_calloc(p, Stmt);
  a->stmt_type = type;
  a->pos = pos;
  return a;
}

Stmt new_stmt_flow(MemPool p, const ae_stmt_t type, const Exp cond, const Stmt body, const m_bool is_do) {
  Stmt a = new_stmt(p, type, loc_cpy(p, cond->pos));
  a->d.stmt_flow.is_do = !!is_do;
  a->d.stmt_flow.cond = cond;
  a->d.stmt_flow.body = body;
  return a;
}

ANN static void free_stmt_flow(MemPool p, struct Stmt_Flow_* a) {
  free_exp(p, a->cond);
  free_stmt(p, a->body);
}

Stmt new_stmt_for(MemPool p, const restrict Stmt c1, const restrict Stmt c2, const restrict Exp c3, const Stmt body) {
  Stmt a = new_stmt(p, ae_stmt_for, loc_cpy(p, c1->pos));
  a->d.stmt_for.c1 = c1;
  a->d.stmt_for.c2 = c2;
  a->d.stmt_for.c3 = c3;
  a->d.stmt_for.body = body;
  return a;
}

ANN static void free_stmt_for(MemPool p, Stmt_For a) {
  free_stmt(p, a->c1);
  free_stmt(p, a->c2);
  if(a->c3)
    free_exp(p, a->c3);
  free_stmt(p, a->body);
}

Stmt new_stmt_auto(MemPool p, struct Symbol_* sym, const Exp exp, const Stmt body) {
  Stmt a = new_stmt(p, ae_stmt_auto, loc_cpy(p, exp->pos));
  a->d.stmt_auto.sym = sym;
  a->d.stmt_auto.exp = exp;
  a->d.stmt_auto.body = body;
  return a;
}

ANN static void free_stmt_auto(MemPool p, Stmt_Auto a) {
  free_exp(p, a->exp);
  free_stmt(p, a->body);
}

Stmt new_stmt_jump(MemPool p, struct Symbol_* xid, const m_bool is_label, const loc_t pos) {
  Stmt a = new_stmt(p, ae_stmt_jump, pos);
  a->d.stmt_jump.name = xid;
  a->d.stmt_jump.is_label = is_label;
  return a;
}

Stmt new_stmt_loop(MemPool p, const Exp cond, const Stmt body) {
  Stmt a = new_stmt(p, ae_stmt_loop, loc_cpy(p, cond->pos));
  a->d.stmt_loop.cond = cond;
  a->d.stmt_loop.body = body;
  return a;
}

ANN static void free_stmt_loop(MemPool p, Stmt_Loop a) {
  free_exp(p, a->cond);
  free_stmt(p, a->body);
}

Stmt new_stmt_if(MemPool p, const Exp cond, const restrict Stmt if_body) {
  Stmt a = new_stmt(p, ae_stmt_if, loc_cpy(p, cond->pos));
  a->d.stmt_if.cond = cond;
  a->d.stmt_if.if_body = if_body;
  return a;
}

ANN static void free_stmt_if(MemPool p, Stmt_If a) {
  free_exp(p, a->cond);
  free_stmt(p, a->if_body);
  if(a->else_body)
    free_stmt(p, a->else_body);
}

Stmt new_stmt_switch(MemPool p, const Exp val, Stmt stmt) {
  Stmt a = new_stmt(p, ae_stmt_switch, loc_cpy(p, val->pos));
  a->d.stmt_switch.val = val;
  a->d.stmt_switch.stmt = stmt;
  return a;
}

ANN static inline void free_stmt_switch(MemPool p, Stmt_Switch a) {
  free_exp(p, a->val);
  free_stmt(p, a->stmt);
}

Stmt new_stmt_enum(MemPool p, const ID_List list, struct Symbol_* xid) {
  Stmt a = new_stmt(p, ae_stmt_enum, loc_cpy(p, list->pos));
  a->d.stmt_enum.xid = xid;
  a->d.stmt_enum.list = list;
  a->d.stmt_enum.flag = 0;
  vector_init(&a->d.stmt_enum.values);
  return a;
}

ANN static void free_stmt_enum(MemPool p, Stmt_Enum a) {
  free_id_list(p, a->list);
  vector_release(&a->values);
}

Stmt new_stmt_union(MemPool p, const Decl_List l, const loc_t pos) {
  Stmt a = new_stmt(p, ae_stmt_union, pos);
  a->d.stmt_union.l = l;
  return a;
}

#ifndef TINY_MODE
#ifdef TOOL_MODE
// TODO: fix me
Stmt new_stmt_pp(MemPool p, const enum ae_pp_type type, const m_str data) {
  Stmt a = new_stmt(p, ae_stmt_pp, 0);
  a->d.stmt_pp.type = type;
  a->d.stmt_pp.data = data;
  return a;
}

ANN static inline void free_stmt_pp(MemPool p, Stmt_PP a) {
  if(a->data)
    xfree(a->data);
}
#endif
#endif

Decl_List new_decl_list(MemPool p, const Exp d, const Decl_List l) {
  Decl_List a = mp_calloc(p, Decl_List);
  a->self = d;
  a->next = l;
  return a;
}

ANN void free_decl_list(MemPool p, Decl_List a) {
  if(a->next)
    free_decl_list(p, a->next);
  if(a->self)
    free_exp(p, a->self);
  mp_free(p, Decl_List, a);
}

ANN static inline void free_stmt_union(MemPool p, Stmt_Union a) {
  if(!GET_FLAG(a, template) && !GET_FLAG(a, global))
    free_decl_list(p, a->l);
}

ANN static inline void free_stmt_jump(MemPool p NUSED, Stmt_Jump a) {
  if(a->is_label && a->data.v.ptr)
    vector_release(&a->data.v);
}

ANN static void free_stmt_xxx(MemPool p NUSED, const union stmt_data *d NUSED) { return; }
typedef void (*_stmt_func)(MemPool, const union stmt_data *);
static const _stmt_func stmt_func[] = {
  (_stmt_func)free_stmt_exp,  (_stmt_func)free_stmt_flow, (_stmt_func)free_stmt_flow,
  (_stmt_func)free_stmt_for,  (_stmt_func)free_stmt_auto, (_stmt_func)free_stmt_loop,
  (_stmt_func)free_stmt_if,   (_stmt_func)free_stmt_code, (_stmt_func)free_stmt_switch,
  (_stmt_func)free_stmt_xxx,  (_stmt_func)free_stmt_xxx,  (_stmt_func)free_stmt_xxx,
  (_stmt_func)free_stmt_xxx,  (_stmt_func)free_stmt_jump,  (_stmt_func)free_stmt_enum,
  (_stmt_func)free_stmt_fptr, (_stmt_func)free_stmt_type, (_stmt_func)free_stmt_union,
#ifndef TINY_MODE
#ifdef TOOL_MODE
  (_stmt_func)free_stmt_pp
#endif
#endif
};

void free_stmt(MemPool p, Stmt stmt) {
  stmt_func[stmt->stmt_type](p, &stmt->d);
  free_loc(p, stmt->pos);
  mp_free(p, Stmt, stmt);
}

Stmt_List new_stmt_list(MemPool p, Stmt stmt, Stmt_List next) {
  Stmt_List list = mp_calloc(p, Stmt_List);
  list->stmt = stmt;
  list->next = next;
  return list;
}

void free_stmt_list(MemPool p, Stmt_List list) {
  if(list->next)
    free_stmt_list(p, list->next);
  free_stmt(p, list->stmt);
  mp_free(p, Stmt_List, list);
}

Section* new_section_stmt_list(MemPool p, const Stmt_List list) {
  Section* a = mp_calloc(p, Section);
  a->section_type = ae_section_stmt;
  a->d.stmt_list = list;
  return a;
}

Section* new_section_func_def(MemPool p, const Func_Def func_def) {
  Section* a = mp_calloc(p, Section);
  a->section_type = ae_section_func;
  a->d.func_def = func_def;
  return a;
}

Section* new_section_class_def(MemPool p, const Class_Def class_def) {
  Section* a = mp_calloc(p, Section);
  a->section_type = ae_section_class;
  a->d.class_def = class_def;
  return a;
}

void free_class_def(MemPool p, Class_Def a) {
  if(a->base.type && GET_FLAG(a, template))
    return;
  if(a->base.ext)
    free_type_decl(p, a->base.ext);
  if(a->base.tmpl)
    free_tmpl(p, a->base.tmpl);
  if(a->body && (!a->base.type || !GET_FLAG(a, ref)))
    free_class_body(p, a->body);
  free_loc(p, a->pos);
  mp_free(p, Class_Def, a);
}

ANN static void free_section(MemPool p, Section* section) {
  const ae_section_t t = section->section_type;
  if(t == ae_section_class)
    free_class_def(p, section->d.class_def);
  else if(t == ae_section_stmt)
    free_stmt_list(p, section->d.stmt_list);
  else if(t == ae_section_func)
    free_func_def(p, section->d.func_def);
  mp_free(p, Section, section);
}

void free_class_body(MemPool p, Class_Body a) {
  if(a->next)
    free_class_body(p, a->next);
  if(a->section)
    free_section(p, a->section);
  mp_free(p, Class_Body, a);
}

Class_Def new_class_def(MemPool p, const ae_flag class_decl, const Symbol xid, Type_Decl* ext,
    const Class_Body body, const loc_t pos) {
  Class_Def a = mp_calloc(p, Class_Def);
  a->flag = class_decl;
  a->base.xid = xid;
  a->base.ext  = ext;
  a->body = body;
  a->pos = pos;
  return a;
}

Class_Body new_class_body(MemPool p, Section* section, const Class_Body body) {
  Class_Body a = mp_calloc(p, Class_Body);
  a->section = section;
  a->next = body;
  return a;
}

Type_List new_type_list(MemPool p, Type_Decl* td, const Type_List next) {
  Type_List a = mp_calloc(p, Type_List);
  a->td   = td;
  a->next = next;
  return a;
}

void free_type_list(MemPool p, Type_List a) {
  if(a->next)
    free_type_list(p, a->next);
  free_type_decl(p, a->td);
  mp_free(p, Type_List, a);
}

Ast new_ast(MemPool p, Section* section, const Ast next) {
  Ast ast = mp_calloc(p, Ast);
  ast->section = section;
  ast->next = next;
  return ast;
}

void free_ast(MemPool p, Ast a) {
  if(a->next)
    free_ast(p, a->next);
  free_section(p, a->section);
  mp_free(p, Ast, a);
}
