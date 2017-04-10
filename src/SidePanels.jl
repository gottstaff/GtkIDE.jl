function add_side_panel(w::Gtk.GtkWidget,title::AbstractString)
    push!(sidepanel_ntbook,w)
    set_tab_label_text(sidepanel_ntbook,w,title)
end
function give_me_a_treeview(n,rownames)

    t = ntuple(i->AbstractString,n)
    list = GtkTreeStore(t...)

    tv = GtkTreeView(GtkTreeModel(list))

    cols = Array(GtkTreeViewColumn,0)

    for i=1:n
        r1 = GtkCellRendererText()
        c1 = GtkTreeViewColumn(rownames[i], r1, Dict([("text",i-1)]))
        Gtk.G_.sort_column_id(c1,i-1)
        push!(cols,c1)
        Gtk.G_.max_width(c1,Int(200/n))
        push!(tv,c1)
    end

    return (tv,list,cols)
end

#### FILES PANEL

include("FilesPanel.jl")

#### WORKSPACE PANEL

type WorkspacePanel <: GtkScrolledWindow

    handle::Ptr{Gtk.GObject}
    list::GtkTreeStore
    tree_view::GtkTreeView

    function WorkspacePanel()

        (tv,list,cols) = give_me_a_treeview(2,["Name","Type"])

        sc = GtkScrolledWindow()
        push!(sc,tv)

        t = new(sc.handle,list,tv)
        Gtk.gobject_move_ref(t,sc)
    end
end

function update!(w::WorkspacePanel)

    function gettype(s::Symbol)
        try
            return string(typeof(getfield(Main,s)))
        end
        ""
    end

    n = sort!(names(Main))
    t = map(gettype,n)
    n = map(string,n)
    M = sortrows([t n])#FIXME use tree view sorting?
    n = M[:,2]
    t = M[:,1]

    sel_val = selected(w.tree_view,w.list)

    empty!(w.list)
    for i = 1:length(t)
        push!(w.list,(n[i],t[i]))
    end

    sel_val != nothing && select_value(w.tree_view,w.list,sel_val)
end

#this is call from MainWindow
function on_path_change(w::WorkspacePanel)#FIXME need a  place to update
    
end
