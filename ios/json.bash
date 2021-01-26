# -*- mode:shell-script;coding:utf-8 -*-
####
#### bash functions to parse json into shell data.
####
#### Note: MacOSX has only bash 3.2, not bash 4.1+, therefore it is
#### lacking associative arrays that would have helped here.  However
#### not completely, since in bash arrays are not first class objects
#### (you cannot store an array in an array).  Therefore we implement
#### here recursive data structures using lower-level primitives.
####
set +o posix

function exitIfScript(){
    local status="${1-$?}"
    case $- in
        (*i*) return "$status" ;;
        (*)   exit   "$status" ;;
    esac
}
if [[ ${bashUtil_PROVIDED:-false} = false ]] ; then
    if [ -z "${COMP_PATH_Scripts-}" ] ; then
        cd "${BASH_SOURCE%/*}/../../../../../../build/tools/Scripts" >/dev/null || exitIfScript $?
        COMP_PATH_Scripts="$(pwd -P)"
        cd - >/dev/null
    fi
    source "${COMP_PATH_Scripts}/bashUtil.sh"
fi


# Supports:
#   strings:      "example"
#   dictionaries: { "key1" : <json1>, "key2" : <json2> }
#   arrays:       [ <json1>, <jsonN> ]


################################################################################
### Primitives
################################################################################

json_exit=exit
json_exit=return

#
# To avoiding having to fork a new process when calling functions,
# notably functions returning results, (which is slow, and impossible
# in the case of mutators), we use a stack upon which the results are
# pushed, and from which the callers can pop the results.
#
# Note: pop is a mutator, so it won't return anything, but update the
# stack and the top variables.  Caller idiom will be:
#
# create_something;result=$top;pop
#
#
# Note: profiling indicates that passing parameters to bash functions
# takes a lot of time. So for functions that are called a lot
# (eg. json parser functions, basically parsing character by
# character), we will avoid function parameter and rely on a few
# global variables.
#

nil=(symbol nil)

# A global stack, used to pass parameters and results between low-level functions
# and thus avoiding slower local parameters or dead slow subshell forking.
declare -i sp=0
declare -i mark=0
declare -a stack=(nil nil nil nil nil nil nil nil nil nil nil nil nil nil nil nil
                  nil nil nil nil nil nil nil nil nil nil nil nil nil nil nil nil
                  nil nil nil nil nil nil nil nil nil nil nil nil nil nil nil nil
                  nil nil nil nil nil nil nil nil nil nil nil nil nil nil nil nil

                  nil nil nil nil nil nil nil nil nil nil nil nil nil nil nil nil
                  nil nil nil nil nil nil nil nil nil nil nil nil nil nil nil nil
                  nil nil nil nil nil nil nil nil nil nil nil nil nil nil nil nil
                  nil nil nil nil nil nil nil nil nil nil nil nil nil nil nil nil

                  nil nil nil nil nil nil nil nil nil nil nil nil nil nil nil nil
                  nil nil nil nil nil nil nil nil nil nil nil nil nil nil nil nil
                  nil nil nil nil nil nil nil nil nil nil nil nil nil nil nil nil
                  nil nil nil nil nil nil nil nil nil nil nil nil nil nil nil nil

                  nil nil nil nil nil nil nil nil nil nil nil nil nil nil nil nil
                  nil nil nil nil nil nil nil nil nil nil nil nil nil nil nil nil
                  nil nil nil nil nil nil nil nil nil nil nil nil nil nil nil nil
                  nil nil nil nil nil nil nil nil nil nil nil nil nil nil nil nil)


# All the stack operations update the top variables to have the same
# value as the top of stack.
top=nil


function stack(){
    # Prints the active stack.
    echo "${stack[@]:0:$sp}"
}


function push(){
    # Pushes the arguments onto the stack.
    # push 1 2 3 == push 1 ; push 2 ; push 3   # 3 is top of stack.
    for value ; do
        sp=$((sp+1))
        stack[${sp}]="$value"
    done
    top="${stack[$sp]:-nil}"
}

function pop(){
    # Pops one element from the stack. top is the new top of stack.
    stack[$sp]=nil
    sp=$((0<sp?sp-1:sp))
    top="${stack[$sp]:-nil}"
}

function dup(){
    # dup [n]
    # e(n) e(n-1) … e(1) -- e(n) e(n-1) … e(1) e(n)
    # Duplicates an element of the stack.
    # If the parameter n is absent or 1, then the top of stack is duplicated,
    # otherwise the nth element down the stack is duplicated onto the top of the stack.
    local i=0
    if [[ $# -eq 1 ]] ; then
        i="$1"
    fi
    sp=$((sp+1))
    stack[$sp]="${stack[${sp}-${i}-1]}"
    top="${stack[$sp]:-nil}"
}

function swap(){
    # swap [n]
    # e(n) e(n-1) … e(1) e(0) -- e(0) e(n-1) … e(1) e(n)
    # Exchanges the top of stack with the element just below it,
    # or if the parameter n is present, the nth element below it,
    local i=1
    if [[ $# -eq 1 ]] ; then
        i="$1"
    fi
    local t="${stack[${sp}-${i}]}"
    stack[${sp}-${i}]="$top"
    stack[${sp}]="$t"
    top="$t"
}

function top(){
    # top
    # update the top variable and prints the top of stack.
    top="${stack[${sp}]:-nil}"
    echo "${top}"
}


# mark and free implement a crude wholesale memory management,
# allowing us to free objects on the stack back down to the last saved mark.

function mark(){
    # mark
    # Saves the stack pointer into the mark variable.
    mark=${sp}
}

function free(){
    # free
    # Pops all the element of the stack above the mark.
    while [[ ${mark} -lt ${sp} ]] ; do
        pop
    done
}



################################################################################
### bash data structure to represent lists, and dictionaries
################################################################################

# A cell is an array variable holding  a type, and a value.  cons cell
# contain  two  values, arbitrarily  named  a  and  d (l'avant  et  le
# derrière).  They are used as  references to their value, storing the
# variable names in other arrays to build hiearchical data structures.

json_next_cell=${json_next_cell:-0}
cell_type=
cell_value=

function cell-type(){
    eval cell_type="\${$1[0]}"
}

function cell-value(){
    eval cell_value="\${$1[1]}"
}

function make_cell(){
    # a normal cell has two slots: type value
    local type="$1"
    local value="$2"
    local cell=cell${json_next_cell}
    eval "${cell}[0]=\${type}"
    eval "${cell}[1]=\${value}"
    json_next_cell=$(( $json_next_cell + 1 ))
    push "$cell"
}

function cell-dump(){
    # Debugging: dumps the cell contents.
    for cell ; do
        printf "\ncell:        %s\n" "$cell"
        printf "cell length: %d\n" "$(eval echo \${#${cell}[@]})"
        printf "cell type:   %s\n" "$(eval echo \${${cell}[0]})"
        cell-type $cell
        if [[ $cell_type = cons ]] ; then
            printf "cell car:    %s\n" "$(eval echo \${${cell}[1]})"
            printf "cell cdr:    %s\n" "$(eval echo \${${cell}[2]})"
        else
            printf "cell value:  %s\n" "$(eval echo \${${cell}[1]})"
        fi
    done
}


function box(){
    # box $value
    # -- bash_cell
    # Creates a cell for random bash values.
    make_cell bash "$1"
}

function unbox(){
    # unbox
    # bash_cell --
    # Pops the bash_cell, check it's type, and extract its value
    # post: cell_type=bash; cell_value = bash value that was in the box.
    local cell=$top
    check-type $cell bash
    cell-value $cell
}


function plus(){
    # plus
    # a b -- a+b
    # unbox a and b and box their sum.
    unbox;local a="$cell_value";pop
    unbox;local b="$cell_value";pop
    box $((a+b))
}

function minus(){
    # minus
    # a b -- a-b
    # unbox a and b and box their difference.
    unbox;local a="$cell_value";pop
    unbox;local b="$cell_value";pop
    box $((a-b))
}

function times(){
    # times
    # a b -- a*b
    # unbox a and b and box their product.
    unbox;local a="$cell_value";pop
    unbox;local b="$cell_value";pop
    box $((a*b))
}

function divide(){
    # divide
    # a b -- a/b
    # unbox a and b and box their division.
    unbox;local a="$cell_value";pop
    unbox;local b="$cell_value";pop
    box $((a/b))
}

function add1(){
    # add1
    # n -- n+1
    box 1;plus
}

function minus1(){
    # minus1
    # n -- n-1
    box 1;minus
}


function cons(){
    # cons
    # a d -- c
    # Pops two objects, and pushes a cons cell with a and d set to those two objects.
    local d=$top;pop
    local a=$top;pop
    local cell=cell${json_next_cell}
    # a cons cell has three slots: type a d
    eval "${cell}[0]=cons"
    eval "${cell}[1]=\${a}"
    eval "${cell}[2]=\${d}"
    json_next_cell=$(( $json_next_cell + 1 ))
    push "$cell"
}

function car(){
    # car
    # c -- a
    # Pops a cons cell, and pushes its a field.
    local c="$top";pop
    if [[ "$c" = nil ]] ; then
        echo nil
    else
        check-type "$c" cons
        eval "push \${$c[1]}"
    fi
}

function cdr(){
    # cdr
    # c -- d
    # Pops a cons cell, and pushes its d field.
    local c=$top;pop
    if [[ "$c" = nil ]] ; then
        echo nil
    else
        check-type "$c" cons
        eval "push \${$c[2]}"
    fi
}

function setcar(){
    # setcar
    # c v --
    # Mutates the a field of the cons cell c, setting it to the value v.
    local v=$top;pop
    local c=$top;pop
    check-type "$c" cons
    eval $c[1]="\$v"
}

function setcdr(){
    # setcdr
    # c v --
    # Mutates the d field of the cons cell c, setting it to the value v.
    local v=$top;pop
    local c=$top;pop
    check-type "$c" cons
    eval $c[2]="\$v"
}

function poplist(){
    # poplist n
    # e1 … en -- list
    # Pops n  elements from the stack  and pushes back a  list made of
    # cdr-chained cons cells with the elements in the cars,
    # Example: box 1;box 2;box 3;box 4;poplist 4;prin1 --> (1 2 3 4)
    local n="$1"
    local list=nil
    local e
    while [[ $n -gt 0 ]] ; do
        n=$((n-1))
        e=$top; push $list ; cons ; list=$top;pop
    done
    push $list
}

function terpri(){
    # terpri
    # Prints a new line
    printf '\n'
}

function prin1(){
    # prin1
    # object --
    # Prints the objects, which can be:
    #   - a cons cell      (a . d)  or (e1 e2 … en) if the cdrs form a chain of cons cell terminated with nil.
    #                       a, d, e1, e2 … en are printed themselves recursively with prin1.
    #   - a string         "string"
    #   - a symbol         symbol
    #   - a bash box       value in the box as printed by echo.
    local object=$top;pop
    local sep=""
    local i
    local c
    local val
    local buffer
    cell-type $object
    case $cell_type in
        cons)
            echo -n "("
            while [[ $object != nil && $cell_type = cons ]] ; do
                echo -n "${sep}";sep=" "
                push $object ; dup ; car ; prin1 ; cdr ; object=$top ; pop
                cell-type $object
            done
            if [[ $object != nil ]] ; then
                echo -n " . "
                push $object ; prin1
            fi
            echo -n ")"
            ;;
        bash)
            cell-value $object
            echo -n $cell_value
            ;;
        symbol) # TODO: should escape separators.
            cell-value $object
            echo -n $cell_value
            ;;
        string)
            string-value $object
            buffer=""
            case "$cell_value" in
                *[\\\"]*)
                    i=0
                    buffer="${buffer}\""
                    while [[ $i -lt ${#cell-value} ]] ; do
                        c="${cell-value:${i}:1}"
                        case "$c" in
                            [\\\"])
                                buffer="${buffer}\\${c}"
                                ;;
                            *)
                                buffer="${buffer}${c}"
                                ;;
                        esac
                        i=$((i+1))
                    done
                    buffer="${buffer}\""
                    echo -n "$buffer"
                    ;;
                *)
                    echo -n \""$cell_value"\"
                    ;;
            esac
            ;;
    esac
}

function length(){
    # length
    # list -- n
    # Pops the list, compute its length, and boxes it onto the stack.
    local list=$top
    local l=0
    while [[ $list != nil ]] ; do
        cdr
        list=$top
        l=$((l+1))
    done
    pop
    box $l
}


function last(){
    # last
    # list -- lastcdr
    # Pops the list, find the last cons cell in the cdr chain, and pushes it.
    while [[ $top != nil ]] ; do
        dup;cdr
        if [[ $top = nil ]] ; then
            pop
            break
        else
            swap;pop
        fi
    done
}

function nconc(){
    # nconc
    # head tail -- concatenated-list
    # Pops two  lists head and  tail, and mutate  the cdr of  the last
    # cons cell of  the head to point to tail,  thus concatenating the
    # two lists.  Pushes the concatenated list.
    swap
    if [[ $top = nil ]] ; then
        pop
    else
        dup;last     # -- tail head (last head)
        swap;swap 2  # -- head (last head) tail
        setcdr
    fi
}

function reverse-push(){
    # reverse-push
    # list -- e(1) e(2) … e(n)
    # Pops the list and pushes the elements in the list, with the last on the top.
    local list=$top
    if [[ $list = nil ]] ; then
        pop
    else
        dup ; car ; swap ; cdr ; reverse-push
    fi
}

function reverse(){
    # reverse
    # list -- reversed-list
    # Creates a new reversed-list, with the elements of the list in the reversed order.
    push nil ; swap # -- new old
    while [[ $top != nil ]] ; do
        dup ; car ; swap ; cdr # new (car old) (cdr old)
        swap 2 # (cdr old) (car old) new
        cons ; swap # -- (cons (car old) new) (cdr old)
    done
    pop
}



function mapcar(){
    # mapcar f
    # list -- newlist
    # Creates a newlist with the results of calling the function f on each element of the list in turn.
    # Example:
    #     box 1;box 2;box 3;box 100;poplist 4
    #     dup;prin1;terpri           --> (1 2 3 100)
    #     mapcar add1;prin1;terpri   --> (2 3 4 101)
    local fun="$1" # a bash function: element -- newelement  to process elements of the list.
    local result=nil
    while [[ $top != nil ]] ; do
        dup;cdr;swap;car
        $fun
        push $result;cons;result=$top;pop
    done
    pop
    push $result;reverse
}


function identity(){
    # identity
    # n -- n
    # a function that doesn't change the stack.
    :
}

function remove-if(){
    # remove-if $predicate [$key]
    # list -- filteredList
    # Remove the element in the list for which the predicate function
    # (applied on the result of the key function) applied on the
    # element of the list, returns a non nil object (on the stack).
    local predicate="$1"
    local key=identity
    if [[ $# -ge 2 ]] ; then
        key=$2
    fi
    local result=nil
    while [[ $top != nil ]] ; do
        dup;cdr;swap;car
        dup;$key;$predicate
        if [[ $top = nil ]] ; then
            pop
            # keep the element
            push $result;cons;result=$top;pop
        else
            pop
            # skip the element
            pop
        fi
    done
    pop
    push $result;reverse
}



function assoc(){
    # assoc
    # alist key -- entry
    # Searches in the alist an entry matching the key, and returns it, or nil if not found.
    # Alists are lists of cons cells containing the key and the value.
    # Example:
    #     make-string Hello;make-string Salut;cons
    #     make-string Bye;make-string 'Au revoir';cons
    #     poplist 2;dup;prin1;terpri                      # --> (("Hello" . "Salut") ("Bye" . "Au revoir"))
    #     dup;make-string Bye;assoc;prin1;terpri          # --> ("Bye" . "Au revoir")
    #     dup;make-string Foo;assoc;prin1;terpri          # --> nil
    #     make-string Hello;assoc;cdr;prin1;terpri        # --> "Salut"

    local key=$top;pop
    cell-value $key
    local kval="$cell_value"
    while [[ $top != nil ]] ; do
        dup ; cdr ; swap ; car # -- (cdr alist) (car alist)
        dup ; car # -- (cdr alist) (car alist) (car (car alist))
        cell-value $top
        if [[ "$cell_value" = "$kval" ]] ; then
            pop;swap;pop
            break
        fi
        pop;pop
    done
}


# make-string one ; box 1 ; cons ; make-string two ; box 2 ; cons ; make-string three ; box 3 ; cons ; poplist 3 ; dup ; prin1; terpri
# make-string two ; assoc ; stack ; prin1 ; terpri
# box 1 ; box 2 ; box 3 ; box 4 ; poplist 4 ; dup ; prin1 ; terpri ; reverse ; prin1 ; terpri
# free ; box 1 ; box 21 ; box 22 ; box 23 ; poplist 3 ; box 30 ; box 31 ; cons ; box 4 ; poplist 4  ; prin1 $top ; terpri

function test-cons(){
    local l
    local c
    box 1 ; box 2 ; box 3 ; push nil ; cons ; cons ; cons
    if [[ $(car $c) -ne 1 ]] ; then json-parser-error "(car (cons 1 (cons 2 (cons 3 nil)))) should be 1, not $(car $c)" ; fi
    if [[ $(car $(cdr $c) ) -ne 2 ]] ; then json-parser-error "(car (cdr (cons 1 (cons 2 (cons 3 nil))))) should be 2, not $(car $(cdr $c) )" ; fi
    if [[ $(car $(cdr $(cdr $c) ) ) -ne 3 ]] ; then json-parser-error "(car (cdr (cdr (cons 1 (cons 2 (cons 3 nil)))))) should be 3, not $(car $(cdr $(cdr $c) ) )" ; fi
    if [[ $(cdr $(cdr $(cdr $c) ) ) != nil ]] ; then json-parser-error "(cdr (cdr (cdr (cons 1 (cons 2 (cons 3 nil)))))) should be nil, not $(cdr $(cdr $(cdr $c) ) )" ; fi
}

function type-error(){
    # Signals a type error.
    local cell="$1"
    local type="$2"
    cell-type "$cell"
    cell-value "$cell"
    printf "TYPE ERROR: expected a %s, got a %s: %s\n" "$type" "$cell_type" "$cell_value" >&2
    $json_exit 1
}

function check-type(){
    # check-type $cell $type
    # Checks that the cell is of the given type. If not a type-error is signaled.
    local cell="$1"
    local type="$2"
    cell-type "$cell"
    if [ "$cell_type" != "$type" ] ; then
        type-error "$cell" "$type"
    fi
}

function make-string(){
    # make-string $string
    # -- string
    # Makes a string cell.
    make_cell string "$@"
}

function string-value(){
    # string
    local cell="$1"
    check-type "$cell" string
    cell-value "$cell"
}

function test-string(){
    local bs='Hello "World"'
    make-string "$bs"
    local s=$top;pop
    string-value $s
    if [[ "$bs" != "$cell_value" ]] ; then
        json-parser-error "make-string didn't make the right string, got $cell_value instead of $bs"
        $json_exit
    fi
}

function json-parser-error(){
    local message="$@"
    printf "PARSER ERROR: %s\n" "$message" >&2
    $json_exit 1
}


# To avoid passing slowly parameters, we use a those global variables
# for the parser:
parse_json_input=""
declare -i parse_json_input_length=0
declare -i parse_json_input_position=0

function json-parser-skip-spaces(){
    while [[ ${parse_json_input_position} -lt ${parse_json_input_length} && "${parse_json_input:${parse_json_input_position}:1}" = *[$' \t\n']* ]] ; do
        parse_json_input_position=$((parse_json_input_position+1))
    done
}

function json-parser-expect-eof(){
    json-parser-skip-spaces
    if [[ ${parse_json_input_position} -ne ${parse_json_input_length} ]] ; then
        json-parser-error "At position ${parse_json_input_position}, expected EOF, found: ${parse_json_input:${parse_json_input_position}:30}"
    fi
}

function parse-json-assoc(){
    # Parses a JSON dictionary entry:
    # key ':' value -- (cons key value)
    local start=${parse_json_input_position}
    # echo parse-json-assoc $p #PJB#DEBUG#
    parse-json-1
    json-parser-skip-spaces
    local c="${parse_json_input:${parse_json_input_position}:1}"
    if  [[ ${parse_json_input_position} -lt ${parse_json_input_length} && "$c" = ':' ]] ; then
        parse_json_input_position=$((parse_json_input_position+1))
        parse-json-1
        cons
    else
        json-parser-error "At position ${parse_json_input_position}, invalid syntax in dictionary entry starting at position ${start} with: ${parse_json_input:${start}:30}"
    fi
}

function parse-json-dictionary(){
    # '{' [ key ':' value { ',' key ':' value } ] '}'
    # echo parse-json-dictionary $p #PJB#DEBUG#
    local l=0
    local start=${parse_json_input_position}
    parse_json_input_position=$((parse_json_input_position+1))
    json-parser-skip-spaces
    local c
    if [[ ${parse_json_input_position} -ge ${parse_json_input_length} ]] ; then
        json-parser-error "At position ${parse_json_input_position}, unterminated dictionary starting at position ${start} with: ${parse_json_input:${start}:30}"
    else
        c="${parse_json_input:${parse_json_input_position}:1}"
        if [[ "$c" = '}' ]] ; then
            # empty dictionary
            push nil
            parse_json_input_position=$((parse_json_input_position+1))
        else
            l=1
            parse-json-assoc
            json-parser-skip-spaces
            c="${parse_json_input:${parse_json_input_position}:1}"
            while [[ ${parse_json_input_position} -lt ${parse_json_input_length} && "$c" = ',' ]] ; do
                l=$((l+1))
                parse_json_input_position=$((parse_json_input_position+1))
                parse-json-assoc
                json-parser-skip-spaces
                c="${parse_json_input:${parse_json_input_position}:1}"
            done
            poplist $l
            #echo -n 'parse-json-dictionary: ';dup;prin1;terpri #DEBUG#

            if [[ ${parse_json_input_position} -lt ${parse_json_input_length} && "$c" = '}' ]] ; then
                parse_json_input_position=$((parse_json_input_position+1))
            elif [[ ${parse_json_input_position} -ge ${parse_json_input_length} ]] ; then
                json-parser-error "At position ${parse_json_input_position}, unterminated dictionary starting at position ${start} with: ${parse_json_input:${start}:30}"
            else
                json-parser-error "At position ${parse_json_input_position}, invalid syntax in dictionary starting at position ${start} with: ${parse_json_input:${start}:30}"
            fi
        fi
    fi
}

function parse-json-array(){
    #  '[' [ value { ',' value } ] ']'
    #echo parse-json-array $p #PJB#DEBUG#
    local l=0
    local start=${parse_json_input_position}
    parse_json_input_position=$((parse_json_input_position+1))
    json-parser-skip-spaces
    local c="${parse_json_input:${parse_json_input_position}:1}"
    if [[ ${parse_json_input_position} -ge ${parse_json_input_length} ]] ; then
        json-parser-error "At position ${p}, unterminated array starting at position ${start} with: ${parse_json_input:${start}:30}"
    else
        if [[ "$c" = ']' ]] ; then
            #empty array
            push nil
            parse_json_input_position=$((parse_json_input_position+1))
        else
            l=1
            parse-json-1
            json-parser-skip-spaces
            c="${parse_json_input:${parse_json_input_position}:1}"
            while [[ ${parse_json_input_position} -lt ${parse_json_input_length} && "$c" = ',' ]] ; do
                l=$((l+1))
                parse_json_input_position=$((parse_json_input_position+1))
                parse-json-1 # next element
                json-parser-skip-spaces
                c="${parse_json_input:${parse_json_input_position}:1}"
            done
            poplist $l
            #echo -n 'parse-json-array: ';dup;prin1;terpri #DEBUG#
            if [[ ${parse_json_input_position} -lt ${parse_json_input_length} && "$c" = ']' ]] ; then
                parse_json_input_position=$((parse_json_input_position+1))
            elif [[ ${parse_json_input_position} -ge ${parse_json_input_length} ]] ; then
                json-parser-error "At position ${parse_json_input_position}, unterminated array starting at position ${start} with: ${parse_json_input:${start}:30}"
            else
                json-parser-error "At position ${parse_json_input_position}, invalid syntax in array starting at position ${start} with: ${parse_json_input:${start}:30}"
            fi
        fi
    fi
}

function parse-json-string(){
    #echo parse-json-string $p #PJB#DEBUG#
    local len
    local start=${parse_json_input_position}
    parse_json_input_position=$((parse_json_input_position+1))
    local c="${parse_json_input:${parse_json_input_position}:1}"
    while [[ ${parse_json_input_position} -lt ${parse_json_input_length} && "$c" != '"' ]] ; do
        # echo char ${p} ${input:${p}:1} #DEBUG#
        if [[ "$c" = '\' ]] ; then
            parse_json_input_position=$((parse_json_input_position+2))
        else
            parse_json_input_position=$((parse_json_input_position+1))
        fi
        c="${parse_json_input:${parse_json_input_position}:1}"
    done
    if [[ ${parse_json_input_position} -lt ${parse_json_input_length} && "$c" = '"' ]] ; then
        parse_json_input_position=$((parse_json_input_position+1))
        len=$((parse_json_input_position-start))
        eval text="${parse_json_input:${start}:${len}}"
        make-string "$text"
    else
        json-parser-error "Unterminated string starting with: ${parse_json_input:${start}:30}"
    fi
}

function parse-json-1(){
    #echo parse-json-1 #PJB#DEBUG#
    json-parser-skip-spaces
    local c="${parse_json_input:${parse_json_input_position}:1}"
    case "$c" in
        '{')
            parse-json-dictionary
            ;;
        '[')
            parse-json-array
            ;;
        '"')
            parse-json-string
            ;;
        *)
            json-parser-error "At position ${parse_json_input_position} invalid character '${c}'."
            ;;
    esac
    #echo -n 'parse-json-1: ';dup 1;prin1;terpri #DEBUG#
}

#
# Cache
#

parse_json_cache_inputs=()
parse_json_cache_results=()

function parse-json-clear-cache(){
    parse_json_cache_inputs=()
    parse_json_cache_results=()
}

function parse-json-cache(){
    local i=0
    local found=0
    for cached in "${parse_json_cache_inputs[@]}" ; do
        if [ "$cached" = "${parse_json_input}" ] ; then
            push ${parse_json_cache_results[$i]}
            found=1
            break
        fi
        i=$((i+1))
    done
    if [[ $found -eq 0 ]] ; then
        parse-json-1
        json-parser-expect-eof
        parse_json_cache_inputs[1+${#parse_json_cache_inputs}]="${parse_json_input}"
        parse_json_cache_results[${#parse_json_cache_inputs}]="$top"
    fi
}

function parse-json(){
    parse_json_input="$1"
    parse_json_input_length=${#parse_json_input}
    parse_json_input_position=0
    parse-json-cache
}



### --- tests ---

function test-push(){
    local s=$sp
    push a
    check-test $((s+1)) -eq $sp
    check-test "$top" = "${stack[$sp]}"
    check-test "$top" = a
}

function test-pop(){
    local s=$sp
    local t=$top
    push a
    pop
    check-test $s -eq $sp
    check-test "$top" = "${stack[$sp]}"
    check-test "$top" = "$t"
}

function test-dup(){
    local s=$sp
    local t=$top
    push a
    dup
    check-test $((s+2)) -eq $sp
    check-test "$top" = "${stack[$sp]}"
    check-test "$top" = a
    pop
    check-test $((s+1)) -eq $sp
    check-test "$top" = "${stack[$sp]}"
    check-test "$top" = "a"
    pop
    check-test $s -eq $sp
    check-test "$top" = "${stack[$sp]}"
    check-test "$top" = "$t"
}


### ---

function test-parse-json-check(){
    local json="$1"
    local expected="$2"
    parse-json-clear-cache
    local result="$(parse-json "$json";prin1)"
    if [[ "$result" != "$expected" ]] ; then
        printf "\nTEST FAILED!\n  Parsing:  %s\n  Expected: %s\n  Result:   %s\n\n" "$json" "$expected" "$result"
    fi
}

function test-parse-json(){
    local json
    local result
    local expected

    test-parse-json-check '"Hello"' \
                          '"Hello"'

    test-parse-json-check  '[]' \
                           "nil"
    test-parse-json-check  '  []   ' \
                           "nil"
    test-parse-json-check  '  [    ] ' \
                           "nil"

    test-parse-json-check  '["hello"]' \
                           '("hello")'
    test-parse-json-check  '  [  "hello"  ]   ' \
                           '("hello")'

    test-parse-json-check  '["hello","world","!"]' \
                           '("hello" "world" "!")'
    test-parse-json-check  '  [  "hello" ,  "world","!" ]   ' \
                           '("hello" "world" "!")'

    test-parse-json-check  '  [   "abc"  , "312",["a","b","c"],"cdef" ]' \
                           "(\"abc\" \"312\" (\"a\" \"b\" \"c\") \"cdef\")"


    local json="{
  \"devices\" : {
    \"com.apple.CoreSimulator.SimRuntime.iOS-9-2\" : [
      {
        \"state\" : \"Shutdown\",
        \"availability\" : \" (unavailable, runtime profile not found)\",
        \"name\" : \"iPhone 4s\",
        \"udid\" : \"D9322B17-43D0-4485-86F2-186D2469C699\"
      },
      {
        \"state\" : \"Shutdown\",
        \"availability\" : \" (unavailable, runtime profile not found)\",
        \"name\" : \"iPhone 5\",
        \"udid\" : \"78D91F64-D7EF-4732-88A8-95E0929A6F69\"
      }
    ],
    \"com.apple.CoreSimulator.SimRuntime.iOS-8-4\" : [
      {
        \"state\" : \"Shutdown\",
        \"availability\" : \" (unavailable, runtime profile not found)\",
        \"name\" : \"iPhone 4s\",
        \"udid\" : \"32C294D1-ED8E-490E-86FF-9419DB8231FC\"
      },
      {
        \"state\" : \"Shutdown\",
        \"availability\" : \" (unavailable, runtime profile not found)\",
        \"name\" : \"iPhone 5\",
        \"udid\" : \"7E584EFA-5D87-4278-B80A-608EF15B7398\"
      }
    ]
  }
}
"
    local expected="((\"devices\" (\"com.apple.CoreSimulator.SimRuntime.iOS-9-2\" ((\"state\" . \"Shutdown\") (\"availability\" . \" (unavailable, runtime profile not found)\") (\"name\" . \"iPhone 4s\") (\"udid\" . \"D9322B17-43D0-4485-86F2-186D2469C699\")) ((\"state\" . \"Shutdown\") (\"availability\" . \" (unavailable, runtime profile not found)\") (\"name\" . \"iPhone 5\") (\"udid\" . \"78D91F64-D7EF-4732-88A8-95E0929A6F69\"))) (\"com.apple.CoreSimulator.SimRuntime.iOS-8-4\" ((\"state\" . \"Shutdown\") (\"availability\" . \" (unavailable, runtime profile not found)\") (\"name\" . \"iPhone 4s\") (\"udid\" . \"32C294D1-ED8E-490E-86FF-9419DB8231FC\")) ((\"state\" . \"Shutdown\") (\"availability\" . \" (unavailable, runtime profile not found)\") (\"name\" . \"iPhone 5\") (\"udid\" . \"7E584EFA-5D87-4278-B80A-608EF15B7398\")))))"

    parse-json-clear-cache
    test-parse-json-check "$json" "$expected"

    parse-json-clear-cache
    test-parse-json-check '  [   "abc"  , "312",["a","b","c"],"cdef" ]' \
                          "(\"abc\" \"312\" (\"a\" \"b\" \"c\") \"cdef\")"

    parse-json-clear-cache
    test-parse-json-check '  { "one":"1",  "two"  : "2" , "three":"3"  } '\
                          "((\"one\" . \"1\") (\"two\" . \"2\") (\"three\" . \"3\"))"

}



function test-all(){
    test-push
    test-pop
    test-dup
    test-parse-json
}

test-all


provide json
#### THE END ####
