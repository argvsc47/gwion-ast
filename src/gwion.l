IS       (u|U|l|L)*
SPACE    [ \r\t]
OP       [\?:\$@\+\-\*/%~\<\>\^|&\!=]
LEX_ID   [A-Za-z_][A-Za-z0-9_]*
FILENAME [A-Za-z0-9\-_./]*
NUM      ([0-9]{1,3}+({SPACE}*[0-9]{3})*)
%{
#include <ctype.h>
#include "gwion_util.h"
#include "gwion_ast.h"
#include "dynop.h"
#include "bison_compat.h"
#include "parser.h"

#define gwion_alloc(a,b) xmalloc(a)
#define gwion_realloc(a,b,c) xrealloc(a,b)
#define gwion_free(a,b)  xfree(a)
#define ERRORCODE(a) a
#define YY_FATAL_ERROR(msg) lexer_error(yyscanner, msg, ERRORCODE(100))

#define GWYY_FATAL_ERROR(msg) { lexer_error(yyscanner, msg, ERRORCODE(101)); yyterminate(); }

// there was yynoreturn
ANN void lexer_error(yyscan_t yyscanner, const char*, const uint errorcode);
ANN static char* strip_lit(char* str);
ANN static char* alloc_str(void *, const char* str);
ANN static Symbol alloc_sym(void *, const char* str);
ANN static m_uint htol(const char* str);
ANN static m_uint btol(const char* str);
ANN static void newline(void* data);
ANN static void adjust(void* data);
ANN static uint  get_currline(void* data);
ANN static uint  get_currpos(void* data);
ANN static char* get_currfile(void* data);
ANN static Macro add_macro(void* data, const m_str id);
ANN static m_str strip_include(const m_str line);
ANN static m_str get_current_filename(void*);
ANN2(1,2) static m_bool handle_include(void*, const m_str, YY_BUFFER_STATE);
ANN static m_bool rem_macro(void* data, const m_str id);
ANN static bool has_macro(void* data, const m_str id);
static m_str pp_data(void* data, const m_str id);
ANN static int macro_toggle(void*);
ANN static void macro_end(void*);
ANN2(1,2) static int is_macro(void*, const m_str, YY_BUFFER_STATE);
ANN static void macro_append(void*, const m_str);
ANN static void macro_arg(void* data, const m_str id);

/* macro call args */
ANN static m_bool handle_comma(void* data);
ANN static void handle_lpar(void* data);
ANN static m_bool handle_rpar(void* data);

// we should use yymore instead
ANN static void handle_char(void* data, m_str str);

ANN static m_str strip_comment(Scanner* scan, const m_str str);
ANN static m_str get_arg_text(void* data, const m_str id);
ANN static m_str macro_data(void* data, const m_bool);

ANN static m_uint  atoll_space(m_str, size_t);
ANN static double atof_space(m_str, size_t);
ANN static double exponent_not(m_str, size_t);

static inline Macro scan_has_macro(Scanner *scan, const m_str id);

#define SCAN_LINT(a)     if(scan->ppa->lint)a;
#define SCAN_NOLINT      if(!scan->ppa->lint)
#define GWYY_ISLINT      ((Scanner*)yyextra)->ppa->lint
#define GWYY_DOLINT(a)   if(GWYY_ISLINT) { a; }
#define GWYY_LINT(a,b)   if(GWYY_ISLINT) { yylval->sval = a; return b; }
#define GWYY_NL          if(GWYY_ISLINT) { yylval->sval = NULL; return PP_NL; }

#define GWYY_COMMENT     if(GWYY_ISLINT) { yymore(); continue; }
#define GWYY_COMMENT2    if(GWYY_ISLINT)   { yymore(); YY_USER_ACTION; continue; }
#define GWYY_COMMENT_END BEGIN(INITIAL); if(GWYY_ISLINT) { yylval->sval = strndup(yytext, strlen(yytext) -1); return PP_COMMENT; }

#define GWYY_INCLUDE  GWYY_LINT(strip_include(yytext), PP_INCLUDE) if(handle_include(yyscanner, yytext, YY_CURRENT_BUFFER) < 0)yyterminate();
#define GWYY_UNDEF    GWYY_LINT(strdup(yytext + 7), PP_UNDEF) if(rem_macro(yyscanner, yytext) < 0) yyterminate();

// 23 BEGIN(INITIAL)?
#define GWYY_DEFINE  BEGIN(INITIAL); GWYY_LINT(macro_data(yyscanner, 0), PP_DEFINE) newline(yyscanner); YY_USER_ACTION; BEGIN(INITIAL);
#define GWYY_CALL    GWYY_LINT(macro_data(yyscanner, 1), ID)
#define GWYY_ELSE    GWYY_LINT(NULL, PP_ELSE) BEGIN(macro_toggle(yyscanner));
#define GWYY_ENDIF   GWYY_LINT(NULL, PP_ENDIF) macro_end(yyscanner);
%}
%option noyyalloc noyyrealloc noyyfree
%option noyylineno
%option noyyget_text
%option noyyget_lineno noyyset_lineno
%option noyyget_in
%option noyyget_out noyyset_out
%option noyyget_lval noyyset_lval
%option noyyset_lloc
%option noyyget_debug noyyset_debug
%option bison-bridge reentrant bison-locations
%option prefix="gwion_"
%option yywrap
%option yymore
%option never-interactive batch
%option nobackup nodebug
%x comment
%x define define_arg_start define_arg skip get_arg pragma interp include_start include_end import import_end
%%

#*\" {
  adjust(yyscanner);
  Scanner *scan = yyget_extra(yyscanner);
  vector_add(&scan->hashes, yyleng);
  scan->interp_state++;
  BEGIN(interp);
  return INTERP_START;
}

<interp>\"#* {
  adjust(yyscanner);
  Scanner *scan = yyget_extra(yyscanner);
  size_t len = yyleng;
  short unsigned int hashes = 1;
  while(yytext[--len] == '#')hashes++;
  if(hashes == vector_back(&scan->hashes)) {
    BEGIN(INITIAL);
    yytext[len] = '\0';
    yylval->string.data = alloc_str(yyscanner, yytext);
    yylval->string.delim = vector_pop(&scan->hashes);
    scan->interp_state--;
    return (vector_size(&scan->hashes) != (m_uint)scan->interp_state) ? INTERP_LIT : INTERP_END;
  } else
    yymore();
}

<interp>"\\${" {
  unput('{');
  unput('$');
  for(int i = yyleng - 2; --i; )
    unput(yytext[i - 1]);
  continue;
}

<interp>"${" {
  Scanner *scan = yyget_extra(yyscanner);
  adjust(yyscanner);
  BEGIN(INITIAL);
  yytext[yyleng - 2] = '\0';
  yylval->string.data = alloc_str(yyscanner, yytext);
  yylval->string.delim = vector_back(&scan->hashes);
  return INTERP_LIT;
}
<interp>"\\#"*\" { yymore(); continue; }
<interp>"\\"*\" { yymore(); continue; }
<interp>"\n"     { newline(yyscanner); yymore(); continue; }
<interp>.        { yymore(); continue; }

<get_arg>{SPACE}*","{SPACE}* { adjust(yyscanner); if(handle_comma(yyscanner) < 0) yyterminate(); }
<get_arg>"(" { adjust(yyscanner); handle_lpar(yyscanner); }
<get_arg>")" {
  adjust(yyscanner);
  const m_bool ret = handle_rpar(yyscanner);
  if(ret < 0)
    yyterminate();
  if(ret) {
    BEGIN(INITIAL);
    GWYY_CALL
  }
}
<get_arg>.   { adjust(yyscanner); handle_char(yyscanner, yytext); }

^{SPACE}*#define{SPACE}+{LEX_ID} {
  adjust(yyscanner);
  if(!add_macro(yyscanner, yytext))
    yyterminate();
//  YY_USER_ACTION
  BEGIN(define_arg_start);
}
<define_arg>{LEX_ID} { adjust(yyscanner); macro_arg(yyscanner, yytext); }
<define_arg>{SPACE}*","{SPACE}*    { adjust(yyscanner); }
<define_arg>"..."{SPACE}*")"{SPACE}* { adjust(yyscanner); macro_arg(yyscanner, "__VA_ARGS__"); BEGIN(define); }
<define_arg>" "   { GWYY_FATAL_ERROR(_("Invalid")); }
<define_arg>")"{SPACE}* { adjust(yyscanner); BEGIN(define); }
<define_arg>. { adjust(yyscanner); GWYY_FATAL_ERROR(_("invalid char in macro")); }

<define_arg_start>"("{SPACE}* { adjust(yyscanner); BEGIN(define_arg); };
<define_arg_start>{SPACE}*    { adjust(yyscanner); BEGIN(define); };
<define_arg_start>\\\n        { adjust(yyscanner); yymore(); continue; };
<define_arg_start>\n          { adjust(yyscanner); BEGIN(INITIAL); GWYY_DEFINE; };

<define>\\\n        { YY_USER_ACTION; adjust(yyscanner); yymore(); continue; };
<define>\n          { YY_USER_ACTION; adjust(yyscanner); macro_append(yyscanner, yytext); GWYY_DEFINE; };
<define>.           { YY_USER_ACTION; adjust(yyscanner); yymore(); continue; };

^"#pragma"{SPACE}+ { adjust(yyscanner); BEGIN(pragma); }
<pragma>.*\n { newline(yyscanner); YY_USER_ACTION; yylval->sval = strndup(yytext, strlen(yytext) - 1); BEGIN(INITIAL); return PP_PRAGMA; }

^#ifn?def{SPACE}+{LEX_ID} {
  adjust(yyscanner);
  const m_str str = strstr(yytext, "def");
  const m_bool def = str[-1] == 'n';
  m_str s = str + 3;
  while(isspace(*s))++s;
  GWYY_LINT(strdup(s), def ? PP_IFNDEF : PP_IFDEF)
  while(isspace(*s))++s;
  size_t sz = strlen(s);
  while(isspace(s[--sz]));
  char c[sz + 2];
  strncpy(c, s, sz + 1);
  c[sz + 1] = '\0';
  const bool ret = has_macro(yyscanner, c);
  if((!ret && !def) || (ret && def)) // ret == def ?
    BEGIN(skip);
}

^{SPACE}*#else{SPACE}*\n  { newline(yyscanner); YY_USER_ACTION; GWYY_ELSE }
^{SPACE}*#endif{SPACE}*\n { newline(yyscanner); YY_USER_ACTION; GWYY_ENDIF; BEGIN(INITIAL); }

<skip>\n      { newline(yyscanner); YY_USER_ACTION; }
<skip>^{SPACE}*#else{SPACE}*\n { adjust(yyscanner); BEGIN(macro_toggle(yyscanner)); }
<skip>^{SPACE}*#endif{SPACE}*\n { adjust(yyscanner); macro_end(yyscanner); BEGIN(INITIAL); }
<skip>.*         { adjust(yyscanner); continue;}

<include_end>{SPACE}*\n {
  adjust(yyscanner);
  Scanner *s = yyget_extra(yyscanner);
  PPState *pps = (PPState*)vector_back(&s->pp->state);
  BEGIN(INITIAL);
  yylval->sval = strdup(pps->filename);
  return PP_INCLUDE;
}
<include_end>. {
  lexer_error(yyscanner, _("illegal characters after include"), 0);
  return 1;
}

^{SPACE}*#include{SPACE}+ { adjust(yyscanner); YY_USER_ACTION; BEGIN(include_start); }
<include_start><{FILENAME}> { adjust(yyscanner); GWYY_INCLUDE; /*BEGIN(include_end); */ BEGIN(INITIAL); yylval->sval = strdup(get_current_filename(yyscanner)); return PP_INCLUDE; }
<include_start>. { adjust(yyscanner); lexer_error(yyscanner, _("invalid include. expected #include <filename>"), 102); return 1;}

<import>{LEX_ID}(":["{LEX_ID}"]"){0,1} { adjust(yyscanner); BEGIN(import_end); yylval->sval = strdup(yytext); return PP_IMPORT; }
<import_end>.*\n   { adjust(yyscanner); newline(yyscanner); YY_USER_ACTION; BEGIN(INITIAL); }
^{SPACE}*#import{SPACE}+ { adjust(yyscanner); BEGIN(import); }

^{SPACE}*#undef{SPACE}+{LEX_ID}{SPACE}* { adjust(yyscanner); GWYY_UNDEF }

^{SPACE}*"\n"                       { newline(yyscanner); YY_USER_ACTION; GWYY_NL; continue; }

"#!"             { /*YY_USER_ACTION; */ adjust(yyscanner); BEGIN(comment); }
<comment>\\\n    { newline(yyscanner); YY_USER_ACTION; GWYY_COMMENT2 }
<comment>\n      { newline(yyscanner); YY_USER_ACTION; GWYY_COMMENT_END }
<comment>"!#"    { /*YY_USER_ACTION; */adjust(yyscanner); BEGIN(INITIAL); }
<comment>.       { adjust(yyscanner); GWYY_COMMENT;  }

"\n"                                { newline(yyscanner); YY_USER_ACTION; continue; }
":["                                { adjust(yyscanner); return TMPL;}
{SPACE}*                             { adjust(yyscanner); continue; }
{OP}{1}  { adjust(yyscanner);  yylval->sym = alloc_sym(yyscanner, yytext); return op1(yytext); }
\?{2,}  { adjust(yyscanner);  yylval->sym = alloc_sym(yyscanner, yytext); return OPTIONS; }
{OP}{2}  { adjust(yyscanner);  yylval->sym = alloc_sym(yyscanner, yytext); return op2(yytext); }
{OP}{3}  { adjust(yyscanner);  yylval->sym = alloc_sym(yyscanner, yytext); return op3(yytext); }
{OP}{4,} { adjust(yyscanner);  yylval->sym = alloc_sym(yyscanner, yytext); return DYNOP; }
";"                                 { adjust(yyscanner); return SEMICOLON;}
","                                 { adjust(yyscanner); return COMMA;}
"fun"|"function"                    { adjust(yyscanner); return FUNCTION;}
"typedef"                           { adjust(yyscanner); return TYPEDEF;}
"distinct"                          { adjust(yyscanner); return DISTINCT;}
"funptr"                            { adjust(yyscanner); return FUNPTR;}
"var"                               { adjust(yyscanner); return VAR; }
"new"                               { adjust(yyscanner);  yylval->sym = alloc_sym(yyscanner, yytext); return NEW; }
"spork"                             { adjust(yyscanner);  yylval->sym = alloc_sym(yyscanner, yytext); return SPORK; }
"fork"                              { adjust(yyscanner);  yylval->sym = alloc_sym(yyscanner, yytext); return FORK; }
"union"                             { adjust(yyscanner); return UNION; }

"\\\n"                                { adjust(yyscanner); continue; }
"\\"                                { adjust(yyscanner); return BACKSLASH; }
"("                                 { adjust(yyscanner); return LPAREN; }
")"                                 { adjust(yyscanner); return RPAREN; }
"["                                 { adjust(yyscanner); return LBRACK; }
"]"                                 { adjust(yyscanner); return RBRACK; }
"{"                                 { adjust(yyscanner); return LBRACE; }
"}"                                 {
  adjust(yyscanner);
  Scanner *scan = yyget_extra(yyscanner);
  if(!scan->interp_state)
   return RBRACE;
  BEGIN(interp);
  return INTERP_EXP;
}

"class"                             { adjust(yyscanner); return CLASS;}
"struct"                            { adjust(yyscanner); return STRUCT;}
"trait"                             { adjust(yyscanner); return TRAIT;}
"operator"                          { adjust(yyscanner); return OPERATOR;}
"extends"                           { adjust(yyscanner); return EXTENDS;}
"..."|,{SPACE}*"..."                { adjust(yyscanner); return ELLIPSE;}
"."                                 { adjust(yyscanner); return DOT;}

%{ /* storage modifiers */ %}
"global"                            { adjust(yyscanner); return GLOBAL;}
"static"                            { adjust(yyscanner); return STATIC;}

%{ /* modifiers */ %}
"abstract"                          { adjust(yyscanner); return ABSTRACT;}
"final"                             { adjust(yyscanner); return FINAL;}

%{ /*access modifiers */ %}
"protect"                           { adjust(yyscanner); return PROTECT;}
"private"                           { adjust(yyscanner); return PRIVATE;}
"const"                             { adjust(yyscanner); return CONSTT;}
"late"                              { adjust(yyscanner); return LATE;}

"if"                                { adjust(yyscanner); return IF;}
"else"                              { adjust(yyscanner); return ELSE;}
"break"                             { adjust(yyscanner); return BREAK;}
"continue"                          { adjust(yyscanner); return CONTINUE;}
"return"                            { adjust(yyscanner); return TRETURN;}
"while"                             { adjust(yyscanner); return WHILE;}
"do"                                { adjust(yyscanner); return DO;}
"until"                             { adjust(yyscanner); return UNTIL;}
"repeat"                            { adjust(yyscanner); return LOOP;}
"for"                               { adjust(yyscanner); return FOR;}
"foreach"                           { adjust(yyscanner); return FOREACH;}
"match"                             { adjust(yyscanner); return MATCH;}
"where"                             { adjust(yyscanner); return WHERE;}
"when"                              { adjust(yyscanner); return WHEN;}
"case"                              { adjust(yyscanner); return CASE;}
"enum"                              { adjust(yyscanner); return ENUM;}
"varloop"                           { adjust(yyscanner); return VARLOOP;}
"defer"                             { adjust(yyscanner); return DEFER;}
"try"                               { adjust(yyscanner); return TRY;}
"perform"                           { adjust(yyscanner); return PERFORM;}
"handle"                            { adjust(yyscanner); return HANDLET;}
"retry"                             { adjust(yyscanner); return RETRY;}
{LEX_ID}{SPACE}*("##"{SPACE}*{LEX_ID})*{SPACE}*"##"{SPACE}*{LEX_ID} {
  assert(yyleng > 0);
  adjust(yyscanner);
  char c[yyleng], *buf = c;
  Scanner* scan = yyget_extra(yyscanner);
  GwText text = { .mp=scan->st->p };
  while(*yytext) {
    if(isspace(*yytext) || *yytext == '#') {
      *buf = '\0';
      text_add(&text, pp_data(yyscanner, c));
      while(*yytext && isspace(*yytext))++yytext;
      while(*yytext && *yytext == '#')++yytext;
      while(*yytext && isspace(*yytext))++yytext;
      buf = c;
    } else
     *buf++ = *yytext++;
  }
  *buf = '\0';
  text_add(&text, pp_data(yyscanner, c));
  yylval->sym = alloc_sym(yyscanner, text.str);
  text_release(&text);
  return ID;
}
"#"{SPACE}*{LEX_ID}           {
  adjust(yyscanner);
  ++yytext;
  while(isspace(*yytext))
    ++yytext;
  const m_str text = get_arg_text(yyscanner, yytext);
  if(text) {
    yylval->sval = alloc_str(yyscanner, text);
    return STRING_LIT;
  } else {
lexer_error(yyscanner, "can't stringify non argument token", 0);
//    gw_err(_("can't stringify non argument token '%s'\n"), yytext);
    return 1;
  }
}
"__line__"                          { adjust(yyscanner); yylval->lval = get_currline(yyscanner); return NUM;}
"__file__"                          { adjust(yyscanner); yylval->sval = get_currfile(yyscanner); return STRING_LIT;}

0[xX][0-9a-fA-F]+{IS}?              { adjust(yyscanner); yylval->lval = htol(yytext);                         return NUM;    }
0[bB][0-1]+{IS}?                    { adjust(yyscanner); yylval->lval = btol(yytext);                         return NUM;    }
0[cC][0-7]+{IS}?                    { adjust(yyscanner); yylval->lval = (m_uint)atoll(yytext);                return NUM;    }
{NUM}+{IS}?                         { adjust(yyscanner); yylval->lval = (m_uint)atoll_space(yytext, yyleng);  return NUM;    }
(({NUM}+"."{NUM}*)|({NUM}*"."{NUM}+))[eE][\+\-]{NUM}+ { adjust(yyscanner); yylval->fval = (m_float)exponent_not(yytext, yyleng);  return FLOATT; }
({NUM}+"."{NUM}*)|({NUM}*"."{NUM}+) { adjust(yyscanner); yylval->fval = (m_float)atof_space(yytext, yyleng);  return FLOATT; }
@{LEX_ID}                           { adjust(yyscanner); yylval->sym  = alloc_sym(yyscanner, yytext); return OPID_A; }
{LEX_ID}                            {
  adjust(yyscanner);
  const int ret = is_macro(yyscanner, yytext, YY_CURRENT_BUFFER);
  if(ret < 0)
    yyterminate();
  if(!ret) {
    yylval->sym = alloc_sym(yyscanner, yytext);
    return ID;
  } else
    continue;
}

'(\\.|[^\\'])'                      { adjust(yyscanner); yylval->sval = alloc_str(yyscanner, strip_lit(yytext)); return CHAR_LIT;   }
.                                   { adjust(yyscanner); lexer_error(yyscanner, _("Stray in program"), 102); return 1;}

%% // LCOV_EXCL_LINE
// LCOV_EXCL_LINE
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

ANN static m_uint  atoll_space(m_str str, size_t sz) {
  char base[sz + 1], *tmp = base;
  for(size_t i = 0; i < sz; ++i) {
    const char c = str[i];
    if(c != ' ')
      *tmp++ = c;
  }
  *tmp = '\0';
  return atoll(base);
}

ANN static double atof_space(m_str str, size_t sz) {
  char base[sz + 1], *tmp = base;
  for(size_t i = 0; i < sz; ++i) {
    const char c = str[i];
    if(c != ' ')
      *tmp++ = c;
  }
  *tmp = '\0';
  return atof(base);
}

ANN static double exponent_not(m_str str, size_t sz) {
  char base[sz + 1], *tmp = base;
  for(size_t i = 0; i < sz; ++i) {
    const char c = str[i];
    if(c != ' ')
      *tmp++ = c;
  }
  *tmp = '\0';
  return strtod(base, NULL);
}

ANN Symbol lambda_name(SymTable *const st, const pos_t pos) {
  char c[6 + 1 + num_digit(pos.line) + num_digit(pos.column) + 2];
  sprintf(c, "lambda:%u:%u", pos.line, pos.column);
  return insert_symbol(st, c);
}

ANN Symbol sig_name(const Scanner *scan, const pos_t pos) {
  char c[6 + 1 + num_digit(pos.line) + num_digit(pos.column) + 2];
  sprintf(c, "@sig_%u_%u", pos.line, pos.column);
  return insert_symbol(scan->st, c);
}

ANN void lexer_error(yyscan_t yyscanner, const char *msg, const uint error_code) {
  struct yyguts_t *yyg = (struct yyguts_t*)yyscanner;
  Scanner* scan = (Scanner*)yyg->yyextra_r;
  scanner_error(scan, msg, NULL, NULL, *yyget_lloc(yyscanner), error_code);
}

char* strip_lit(char* str){
  str[strlen(str)-1] = '\0';
  return str+1;
}

Symbol alloc_sym(void *data, const char* str) {
  const Scanner* scan = yyget_extra(data);
  return insert_symbol(scan->st, (m_str)str);
}

char* alloc_str(void *data, const char* str) {
  const Symbol sym = alloc_sym(data, str);
  return s_name(sym);
}


m_uint htol(const char* str) {
  unsigned char * c = (unsigned char*)str;
  m_uint n = 0;

  c += 2;
  while(*c) {
    n <<= 4;
    switch(*c) {
      case '0' ... '9':
        n += (uint)(*c - '0');
        break;
      case 'a' ... 'f':
        n += (uint)(*c - 'a' + 10);
        break;
      case 'A' ... 'F':
        n += (uint)(*c - 'A' + 10);
        break;
    }
    c++;
  }
  return n;
}

m_uint btol(const char* str) {
  m_uint n = 0;
  str += 2;

  for (; *str; str++)
    n = (n * 2) + ((unsigned char)*str - '0');

  return n;
}

static void newline(void* data) {
  Scanner* scan = yyget_extra(data);
  ++scan->pos.line;
  scan->pos.column = 1;
}

static uint get_currline(void* data) {
  const Scanner* scan = yyget_extra(data);
  return scan->pos.line;
}

static uint get_currpos(void* data) {
  const Scanner* scan = yyget_extra(data);
  return scan->pos.column;
}

static char* get_currfile(void* data) {
  const Scanner* scan = yyget_extra(data);
  const PPState *ppstate = (PPState*)vector_back(&scan->pp->state);
  return alloc_str(data, ppstate->filename);
}

static void adjust(void* data) {
  Scanner *scan = yyget_extra(data);
  scan->pos.column += (uint)gwion_get_leng((void*)data);
}

static Macro add_macro(void* data, const m_str line) {
  Scanner* scan = yyget_extra(data);
  const m_str str = strstr(line, "#define");
  int i = 7;
  while(isspace(str[i]))++i;
  loc_t *loc = yyget_lloc(data);
  loc->first.column += i;
  scan->pos.column += i;
  m_str id = strip_comment(data, str + i);
  scan->pp->entry = macro_add(scan->pp->macros, id);
  xfree(id);
  if(!scan->pp->entry) {
    lexer_error(data, "Already defined", ERRORCODE(103));
    return NULL;
  }
  PPState *const ppstate = (PPState*)vector_back(&scan->pp->state);
  scan->pp->entry->file = ppstate->filename;
  ppstate->pos.first = scan->pos;
  ppstate->pos.last = scan->pos;
  scan->pp->entry->pos = yyget_lloc(data)->first;//scan->pos;
  scan->pp->entry->text = mp_calloc(scan->ppa->hash.p, GwText);
  scan->pp->entry->text->mp = scan->ppa->hash.p;
  return scan->pp->entry;
}

static m_str strip_include(const m_str line) {
  const m_str str = line + 1;
  m_str end = strstr(str, ">");
  *end = '\0';
  return strdup(str);
}

static m_str strip_comment(Scanner* scan, const m_str s) {
  m_str str = s;
  while(isspace(*str)) ++str;
  size_t end = strlen(str);
  while(isspace(str[--end]));
  scan->pos.column += (uint)(str - s);
  return strndup(str, end + 1);
}

static inline m_bool scan_rem_macro(Scanner *scan, const m_str id) {
  const Symbol sym = insert_symbol(scan->st, id);
  if(macro_rem(scan->pp->macros, id)) {
    const m_bool ret = ppa_rem_macro(scan->ppa, sym);
    if(!ret)
      vector_add(&scan->pp->global_undef, (vtype)sym);
    return ret;
  }
  return GW_OK;
}

static m_bool rem_macro(void* data, const m_str str) {
  Scanner* scan = yyget_extra(data);
  scan->pos.column += 6;
  const m_str id = strip_comment(scan, str+6);
  const m_bool ret = scan_rem_macro(scan, id);
  xfree(id);
  if(ret > 0)
    return GW_OK;
  lexer_error(data, "Undefined", ERRORCODE(104));
  return GW_ERROR;
}

static inline Macro scan_has_macro(Scanner *scan, const m_str id) {
  const Symbol sym = insert_symbol(scan->st, id);
  const m_int ret = vector_size(&scan->pp->global_undef) ? vector_find(&scan->pp->global_undef, (vtype)sym) : GW_ERROR;
  if(ret != GW_ERROR)
    return NULL;
  const Macro global = ppa_has_macro(scan->ppa, insert_symbol(scan->st, id));
  if(global)
    return global;
  return macro_has(scan->pp->macros, id);
}

static m_str pp_data(void* data, const m_str id) {
  Scanner* scan = yyget_extra(data);
  const m_str arg = get_arg_text(data, id);
  if(arg)
    return arg;
  Macro e = scan_has_macro(scan, id);
  if(e)
    return e->text->str;
  return id;
}

static bool has_macro(void* data, const m_str id) {
  Scanner* scan = yyget_extra(data);
  const bool ret = !!scan_has_macro(scan, id);
  vector_add(&scan->pp->data, ret);
  return ret;
}

static void gwpp_stack(Scanner* scan, YY_BUFFER_STATE state, void* opt,
          const m_str str, const enum pptype type) {
  PPState *ppstate = new_ppstate(scan->st->p, str);
  ppstate->state = state;
  ppstate->data = opt;
  ppstate->pos.first = scan->pos;
  ppstate->pos.last = scan->pos;
  ppstate->type = type;
  vector_add(&scan->pp->state, (vtype)ppstate);
}

static FILE* get_include_from_path(const m_str str, const Vector v) {
  const size_t sz = strlen(str);
  for(m_uint i = 0; i < vector_size(v); ++i) {
    const m_str dir = (m_str)vector_at(v, i);
    char c[strlen(dir) + sz + 2];
    sprintf(c, "%s/%s", dir, str);
    FILE *f = fopen(c, "r");
    if(f) return f;
  }
  return NULL;
}

static bool get_dirname(m_str str, m_str c) {
  m_str end = strrchr(str, '/');
  if(!end) return false;
  strncpy(c, str, end - str);
  c[end - str] = '\0';
  return true;
}

static FILE* get_include(void *data, const m_str str) {
  const m_str filename = get_current_filename(data);
  const size_t _sz = strlen(filename);
  char dir[_sz + 1];
  if(get_dirname(filename, dir)) {
    const size_t sz = strlen(dir);
    char c[strlen(dir) + sz + 2];
    sprintf(c, "%s/%s", dir, str);
    FILE *f = fopen(c, "r");
    if(f) return f;
  }
  Scanner* scan = yyget_extra(data);
  return get_include_from_path(str, &scan->ppa->path);
}

static m_str get_current_filename(void* data) {
  Scanner* scan = yyget_extra(data);
  for(m_uint i = vector_size(&scan->pp->state) + 1; --i;) {
    const PPState *ppstate = (PPState*)vector_at(&scan->pp->state, i - 1);
    if(*ppstate->filename != '@')
      return ppstate->filename;
  }
  return NULL;
}

static m_bool handle_include(void* data, const m_str filename, YY_BUFFER_STATE handle) {
  Scanner* scan = yyget_extra(data);
  const m_str str = strip_include(filename);
  FILE* f = fopen(str, "r") ?: get_include(data, str);
  if(!f) {
    xfree(str);
    lexer_error(data, "file not found", ERRORCODE(105));
    return GW_ERROR;
  }
  gwpp_stack(scan, handle, f, str, pptype_file);
  pos_ini(&scan->pos);
  yy_switch_to_buffer(yy_create_buffer(f, YY_BUF_SIZE, data), data);
  return GW_OK;
}

static m_str macro_data(void* data, const m_bool call) {
  Scanner* scan = yyget_extra(data);
  const Macro e = scan->pp->entry;
  size_t elen = strlen(e->name);
  size_t len = elen + 2;
  MacroArg args = e->base;
  if(args) {
    do {
      const m_str str = call ? args->text.str : args->name;
      len += strlen(str);
      if(args->next)
        len += 2;
    } while((args = args->next));
    len += 2;
  }
  if(!call && e->text->str)
    len += strlen(e->text->str) + 1;
  char c[len];
  size_t offset = elen;
  strcpy(c, e->name);
  args = scan->pp->entry->base;
  if(args) {
    c[offset++] = '(';
    do {
      const m_str str = call ? args->text.str : args->name;
      strcpy(c + offset, str);
      offset += strlen(str);
      if(call)
        text_release(&args->text);
      if(args->next) {
        strcpy(c + offset, ", ");
        offset += 2;
      }
    } while((args = args->next));
    c[offset++] = ')';
  }
  if(!call && e->text->str) {
    c[offset++] = ' ';
    strcpy(c + offset, e->text->str);
    offset += strlen(e->text->str);
  }
  if(c[offset - 1] == '\n')
    c[offset - 1] = '\0';
  else
    c[offset] = '\0';
  scan->pp->entry = NULL;
  return strdup(c);
}

static int macro_toggle(void* data) {
  const Scanner* scan = yyget_extra(data);
  const Vector v= &scan->pp->data;
  const int ret = VPTR(v, VLEN(v)) == !vector_back(v);
  return ret ? INITIAL : skip;
}

static void macro_arg(void* data, const m_str id) {
  Scanner* scan = yyget_extra(data);
  const m_str str = strip_comment(scan, id);
  const MacroArg arg = new_macroarg(scan->st->p, str);
  arg->pos = scan->pos;
  xfree(str);
  if(scan->pp->entry->base) {
    MacroArg a = scan->pp->entry->base;
    while(a->next)
      a = a->next;
    a->next = arg;
  } else
    scan->pp->entry->base = arg;
}

static void macro_end(void* data) {
  const Scanner* scan = yyget_extra(data);
  const Vector v = &scan->pp->data;
  vector_rem(v, VLEN(v) - 1);
}

static m_str concat(const m_str a, const m_str b) {
  const size_t len = strlen(a) + strlen(b) + 4;
  const m_str c = (m_str)xmalloc(len);
  sprintf(c, "%s '%s'", a, b);
  return c;
}

static m_bool is_macro(void* data, const m_str s, YY_BUFFER_STATE handle) {
  Scanner* scan = yyget_extra(data);
  const m_bool is_str = s[0] == '#';
  m_str id = is_str ? s+1 : s;

  for(m_uint i = 0; i < vector_size(&scan->pp->state); ++i) {
    const PPState *ppstate = (PPState*)vector_at(&scan->pp->state, i);
    if(ppstate->filename[0] == '@') {
      char c[strlen(ppstate->filename + 8)];
      memcpy(c, ppstate->filename + 8, strlen(ppstate->filename + 8) - 1);
      c[strlen(ppstate->filename + 8) - 1] = '\0';
      if(!strcmp(s, c)) {
        yywrap(data);
        lexer_error(data, "Recursive use detected", ERRORCODE(106));
        return GW_ERROR;
      }
    }
  }

  const PPState *ppstate = (PPState*)vector_back(&scan->pp->state);
  for(m_uint i = vector_size(&scan->pp->state) + 1; --i;) {
    const PPState *pps = (PPState*)vector_at(&scan->pp->state, i-1);
    if(pps->type != pptype_arg) continue;
    MacroArg arg = pps->arg;
    while(arg) {
      if(!strcmp(id, arg->name)) {
        if(arg->text.str) {
          if(!is_str) {
            SCAN_NOLINT {
              if(ppstate->pos.first.line == arg->pos.line)
                break;
              const m_str str = concat("@argument", arg->name);
              gwpp_stack(scan, handle, arg->orig, str, pptype_handle);// should be reference
              scan->pos = arg->pos;
              yy_scan_string(arg->text.str, data);
              return 1;
            }
          } else {
            if(!strcmp(arg->name, "__VA_ARGS__"))exit(16);// not enough args ?
              return 0;
          }
        }
        return 1;
      }
      arg = arg->next;
    }
  }
  Macro e = scan_has_macro(scan, id);
  if(e) {
  m_str str = NULL;
  scan->pp->entry = e;
  if(e->text->str) {
    if(e->base) {
      e->args = e->base;
//      SCAN_NOLINT
        str = concat("@macro", e->name);
      char c = '@';
      while(isspace(c = (char)input(data)))++scan->pos.column;
        if(c != '(') {
          xfree(str);
          lexer_error(data, "Needs arguments", ERRORCODE(107));
          return GW_ERROR;
        }
        ++scan->pp->npar;
        gwpp_stack(scan, handle, e->base, str, pptype_arg);
        scan->pos = e->pos;
        struct yyguts_t *yyg = (struct yyguts_t*)data;
        yyg->yy_start = 1 + 2 * get_arg;
        void *yyscanner = data;
        YY_USER_ACTION;
        return 2;
      } else {
        SCAN_LINT(return 0);
        const m_str str = concat("@macro", e->name);
        gwpp_stack(scan, handle, e->base, str, pptype_arg);
        scan->pos = e->pos;
        yy_scan_string(e->text->str, data);
        return 1;
      }
    }
    return 1;
  } else if(!strcmp(id, "__VA_ARGS__")) { // vararg macro with no args
    Macro e = scan_has_macro(scan, ppstate->filename);
    if(!e)
      return 0;
    const m_str str = concat("@argument", "__VA_ARGS__");
    gwpp_stack(scan, handle, NULL, str, pptype_handle);
    scan->pos = e->pos;
    yy_scan_string(e->base->text.str, data);
    return 1;
  }
  return 0;
}

static m_str get_arg_text(void* data, const m_str id) {
  const Scanner* scan = yyget_extra(data);
  if(!scan->pp->entry)
    return NULL;
  if(vector_size(&scan->pp->state) == 1)
    return NULL;
  const PPState *ppstate = (PPState*)vector_back(&scan->pp->state);
  if(ppstate->type != pptype_arg) return NULL;
  MacroArg arg = ppstate->arg;
  while(arg) {
    if(!strcmp(id, arg->name))
      return arg->text.str ?: "";
    arg = arg->next;
  }
  return NULL;
}

static void macro_append(void* data, const m_str str) {
  Scanner* scan = yyget_extra(data);
  assert(scan->pp->entry);
  str[strlen(str) - 1] = '\0';
  text_add(scan->pp->entry->text, str);
}

ANN void clear_buffer(void *state, void* scan) {
  PPState *ppstate = (PPState*)state;
  const YY_BUFFER_STATE fini = (YY_BUFFER_STATE)ppstate->state;
  struct yyguts_t *yyg = (struct yyguts_t*)scan;
  YY_BUFFER_STATE curr = yyg->yy_buffer_stack[yyg->yy_buffer_stack_top];
  YY_BUFFER_STATE base = yyg->yy_buffer_stack[0];
  if(ppstate->type == pptype_file)
    fclose(ppstate->file);
  if(fini != base && fini != curr)
    yy_delete_buffer(fini, scan);
  xfree(ppstate->filename);
}

int yywrap(void* data) {
  struct yyguts_t *yyg = (struct yyguts_t*)data;
  YY_BUFFER_STATE handle = yyg->yy_buffer_stack[yyg->yy_buffer_stack_top];
  Scanner *scan = yyget_extra(data);
  if(vector_size(&scan->pp->state) > 1) {
    const PPState *ppstate = (PPState*)vector_pop(&scan->pp->state);
    if(handle != ppstate->state) {
      yy_switch_to_buffer(ppstate->state, data);
      yy_delete_buffer(handle, data);
    }
    if(ppstate->type == pptype_file && ppstate->file) {
//      fclose(ppstate->file);
      BEGIN(include_end);
    } else if(ppstate->type == pptype_arg && ppstate->arg)
      clean_macroarg(ppstate->arg);
    if(strlen(ppstate->filename))
      xfree(ppstate->filename);
    scan->pos = ppstate->pos.last;
    void* yyscanner = data;
    YY_USER_ACTION
    return 0;
  }
  return 1;
}

static m_bool handle_comma(void* data) {
  const Scanner *scan = yyget_extra(data);
  const MacroArg a = scan->pp->entry->args;
  if(strcmp(a->name, "__VA_ARGS__")) {
    if(!(scan->pp->entry->args = a->next)) {
      loc_t *loc = yyget_lloc(data);
      const PPState *ppstate = (PPState*)vector_back(&scan->pp->state);
      *loc = ppstate->pos;
      loc->first.column++;
      loc->last.column++;
      lexer_error(data, "Too many arguments", ERRORCODE(108));
      return GW_ERROR;
    }
  } else handle_char(data, ",");
  return GW_OK;
}

static void handle_lpar(void* data) {
  const Scanner *scan = yyget_extra(data);
  ++scan->pp->npar;
}

static m_bool handle_rpar(void* data) {
  Scanner *scan = yyget_extra(data);
  if(!scan->pp->npar) {
    lexer_error(data, "Invalid ')' token", ERRORCODE(109));
    return GW_ERROR;
  }
  if(--scan->pp->npar)
    return 0;
  if(scan->pp->entry->args->next) {
    PPState *ppstate = (PPState*)vector_back(&scan->pp->state);
    loc_t loc = ppstate->pos;
    loc.first.column++;
    loc.last.column++;
    scanner_error(scan, "not enough arguments", NULL, NULL, loc, ERRORCODE(110));
    return GW_ERROR;
  }
  scan->pp->entry->args = NULL;
  SCAN_NOLINT
    yy_scan_string(scan->pp->entry->text->str, data);
  return 1;
}

static void handle_char(void* data, m_str str) {
  const Scanner *scan = yyget_extra(data);
  while(isspace(*str))++str;
  text_add(&scan->pp->entry->args->text, str);
}
