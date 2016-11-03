# Dynamic binding is invaluable for creating certain kinds of
# complex control flow in an intuitive way. Declare and access
# a dynamic var:

#     @dynamic a = 1
#     a[] #> 1

# Binding `a` alters its value for everywhere further down in
# the stack.

#     showa() = @show a[]
#     @dynamic let a = 2
#       showa()
#     end
#     #> a[] => 2

# Including for sub tasks which may continue to run:

#     function showa()
#       @schedule for i = 1:10
#         @show a[]
#         sleep(1)
#       end
#     end

#     @dynamic let a = 3
#       showa()
#     end

# This will print `a[] => 3` repeatedly, while evluating `a[]`
# will return `1`.

# You can also use the syntax

#     a[] = 5

# which will modify either the most recent binding value or the
# root of the var, as applicable.

# See also Clojure's dynamic vars for the inspiration:
# http://clojure.org/vars

import Base: getindex, setindex!

type Binding{T}
  root::T
end

root(b::Binding) = b.root

function dynamic_eq(def)
  name, val = def.args
  if isexpr(name, :(::))
    name, T = name.args
    :(const $(esc(name)) = Binding{$(esc(T))}($(esc(val))))
  else
    :(const $(esc(name)) = Binding($(esc(val))))
  end
end

function dynamic_let(ex)
  bindings = [:(bind($(esc(b.args[1])), $(esc(b.args[2])), t)) for b in ex.args[2:end]]
  quote
    t = @task $(esc(ex.args[1]))
    $(bindings...)
    schedule(t)
    wait(t)
  end
end

macro dynamic(def)
  isexpr(def, :(=)) ? dynamic_eq(def) :
  isexpr(def, :let) ? dynamic_let(def) :
  error("Unsupported @dynamic expression")
end

parent(t::Task) = t.parent

storage(t::Task) =
  t.storage == nothing ? (t.storage = ObjectIdDict()) :
  t.storage

isroot(task::Task) =
  task.parent == task

bindings(task::Task) =
  get!(storage(task), :bindings, Dict())

bind{T}(b::Binding{T}, v::T, t::Task) =
  bindings(t)[b] = v

function bind{T}(f::Function, b::Binding{T}, v::T)
  t = Task(f)
  bind(b, v, t)
  schedule(t)
  return wait(t)
end

binding{T}(b::Binding{T}, t::Task = current_task()) =
  haskey(bindings(t), b) ? bindings(t)[b]::T :
  isroot(t) ? root(b) : binding(b, parent(t))

set!{T}(b::Binding{T}, v::T, t::Task = current_task()) =
  haskey(bindings(t), b) ? (bindings(t)[b] = v) :
  isroot(t) ? (b.root = v) : set!(b, v, parent(t))

getindex(b::Binding) = binding(b)
setindex!{T}(b::Binding{T}, v::T) = set!(b, v)
