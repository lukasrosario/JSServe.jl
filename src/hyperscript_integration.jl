module DOM

using Hyperscript

const global_unique_dom_id_counter = Ref(0)

"""
    get_unique_dom_id()

We could use a unique ID like uuid4, but since every dom element gets
such an id, I prefer to keep the id as short as possible, so we just use a counter.
"""
function get_unique_dom_id()
    global_unique_dom_id_counter[] += 1
    return string(global_unique_dom_id_counter[])
end

"""
Dome node with unique ID, to make it easier to interpolate it.
"""
function um(tag, args...; kw...)
    m(tag, args..., dataJscallId = get_unique_dom_id(); kw...)
end

function m_unesc(tag, args...; kw...)
    m(Hyperscript.NOESCAPE_HTMLSVG_CONTEXT, tag, args..., dataJscallId = get_unique_dom_id(); kw...)
end

for node in (:a, :abbr, :address, :area, :article, :aside, :audio, :b,
    :base, :bdi, :bdo, :blockquote, :body, :br, :button, :canvas, :caption, :cite, :code, :col, :colgroup, :data, :datalist,
    :dd, :del, :details, :dfn, :dialog, :div, :dl, :dt, :em, :embed, :fieldset, :figcaption, :figure, :footer, :form, :h1, :h2,
    :h3, :h4, :h5, :h6, :head, :header, :hgroup, :hr, :html, :i, :iframe, :img, :input, :ins, :kbd, :label, :legend, :li, :link,
     :main, :map, :mark, :math, :menu, :menuitem, :meta, :meter, :nav, :noscript, :object, :ol, :optgroup, :option, :output, :p, :param,
      :picture, :pre, :progress, :q, :rb, :rp, :rt, :rtc, :ruby, :s, :samp, :script, :section, :select, :slot, :small, :source, :span,
      :strong, :style, :sub, :summary, :sup, :svg, :table, :tbody, :td, :template, :textarea, :tfoot, :th, :thead, :time, :title, :tr,
      :track, :u, :ul, :var, :video, :wbr)
    node_name = string(node)
    unesc = Symbol(node_name * "_unesc")
    @eval $(node)(args...; kw...) = um($(node_name), args...; kw...)
    @eval $(unesc)(args...; kw...) = m_unesc($(node_name), args...; kw...)
end

style(args...; kw...) = m_unesc("style", args...; kw...)
script(args...; kw...) = m_unesc("script", args...; kw...)

end

using .DOM

# default turn attributes into strings
attribute_render(session::Session, parent, attribute::String, x) = string(x)
attribute_render(session::Session, parent, attribute::String, x::Nothing) = x
attribute_render(session::Session, parent, attribute::String, x::Bool) = x

function attribute_render(session::Session, parent, attribute::String, obs::Observable)
    onjs(session, obs, js"""
    function (value){
        var node = $(parent);
        if(node){
            if(node[$attribute] != value){
                node[$attribute] = value;
            }
            return true;
        }else{
            return false; //deregister
        }
    }
    """)
    return attribute_render(session, parent, attribute, obs[])
end

function attribute_render(session::Session, parent, attribute::String, jss::JSCode)
    register_resource!(session, jss)
    return serialize_readable(jss)
end

render_node(session::Session, x) = x

const BOOLEAN_ATTRIUTES = Set([
    "allowfullscreen",
    "allowpaymentrequest",
    "async",
    "autofocus",
    "autoplay",
    "checked",
    "controls",
    "default",
    "defer",
    "disabled",
    "formnovalidate",
    "hidden",
    "ismap",
    "itemscope",
    "loop",
    "multiple",
    "muted",
    "nomodule",
    "novalidate",
    "open",
    "readonly",
    "required",
    "reversed",
    "selected",
    "typemustmatch"
])

is_boolean_attribute(attribute::String) = attribute in BOOLEAN_ATTRIUTES

function render_node(session::Session, node::Node)
    # give each node a unique id inside the dom
    new_attributes = Dict{String, Any}()
    newchildren = map(children(node)) do elem
        childnode = jsrender(session, elem)
        # if a transform elem::Any -> ::Node happens, we need to
        # render the resulting node again, since the attr/children won't be
        # lowered yet!
        if !(elem isa Node)
            childnode = render_node(session, childnode)
        end
        return childnode
    end
    for (k, v) in Hyperscript.attrs(node)
        rendered = attribute_render(session, node, k, v)
        # We code nothing to mean omitting the attribute!
        if is_boolean_attribute(k)
            if rendered isa Bool
                if rendered
                    # only add attribute if true!
                    new_attributes[k] = true
                end
            else
                error("Boolean attribute $(k) expects a boolean! Found: $(typeof(rendered))")
            end
        else
            new_attributes[k] = rendered
        end
    end
    return Node(
        Hyperscript.context(node),
        Hyperscript.tag(node),
        newchildren,
        new_attributes
    )
end

# jsrender(session, x) will be called anywhere...
# if there is nothing sessions specific in the dom, fallback to jsrender without session
function jsrender(session::Session, node::Node)
    render_node(session, node)
end

function uuid(node::Node)
    get(Hyperscript.attrs(node), "data-jscall-id") do
        error("Node $(node) doesn't have a unique id. Make sure to use DOM.$(Hyperscript.tag(node))")
    end
end

"""
    jsrender([::Session], x::Any)
Internal render method to create a valid dom. Registers used observables with a session
And makes sure the dom only contains valid elements. Overload jsrender(::YourType)
To enable putting YourType into a dom element/div.
You can also overload it to take a session as first argument, to register
messages with the current web session (e.g. via onjs).
"""
jsrender(::Session, x::Any) = jsrender(x)
jsrender(::Session, x::Symbol) = DOM.p(string(x))
jsrender(::Session, x::Hyperscript.Styled) = x
jsrender(x) = x
