
function add_side_panel(w::Gtk.GtkWidget,title::AbstractString)
    push!(sidepanel_ntbook,w)
    set_tab_label_text(sidepanel_ntbook,w,title)
end
function files_tree_view(rownames)
    n  = length(rownames)
    t = (Gtk.GdkPixbuf,AbstractString, AbstractString)
    list = @GtkTreeStore(t...)

    tv = @GtkTreeView(GtkTreeModel(list))

    cols = Array(GtkTreeViewColumn,0)

    r1 = @GtkCellRendererPixbuf()
    c1 = @GtkTreeViewColumn(rownames[1], r1, Dict([("pixbuf",0)]))
    Gtk.G_.sort_column_id(c1,0)
    push!(cols,c1)
    Gtk.G_.max_width(c1,Int(200/n))
    push!(tv,c1)

    r2 = @GtkCellRendererText()
    c2 = @GtkTreeViewColumn(rownames[2], r2, Dict([("text",1)]))
    Gtk.G_.sort_column_id(c2,1)
    push!(cols,c2)
    Gtk.G_.max_width(c2,Int(200/n))
    push!(tv,c2)



    return (tv,list,cols)
end
function give_me_a_treeview(n,rownames)

    t = ntuple(i->AbstractString,n)
    list = @GtkTreeStore(t...)

    tv = @GtkTreeView(GtkTreeModel(list))

    cols = Array(GtkTreeViewColumn,0)

    for i=1:n
        r1 = @GtkCellRendererText()
        c1 = @GtkTreeViewColumn(rownames[i], r1, Dict([("text",i-1)]))
        Gtk.G_.sort_column_id(c1,i-1)
        push!(cols,c1)
        Gtk.G_.max_width(c1,Int(200/n))
        push!(tv,c1)
    end

    return (tv,list,cols)
end

import Gtk.selected
function selected(tree_view::GtkTreeView,list::GtkTreeStore)
    selmodel = Gtk.G_.selection(tree_view)
    if hasselection(selmodel)
        iter = selected(selmodel)
        println(iter)
        return list[iter]
    end
    return nothing
end
#select the first entry that is equal to v
function select_value(tree_view::GtkTreeView,list::GtkTreeStore,v)
    selmodel = Gtk.G_.selection(tree_view)
    for i = 1:length(list)
        if list[i] == v
            select!(selmodel, Gtk.iter_from_index(list, i))
            return
        end
    end
end

#### FILES PANEL

function open_file(treeview::GtkTreeView,list::GtkTreeStore)

    v = selected(treeview, list)    
    if v != nothing && length(v) == 3
        isfile(v[3]) && open_in_new_tab(v[3])
        
    end
end

function filespanel_treeview_clicked_cb(widgetptr::Ptr, eventptr::Ptr, user_data)
    treeview = convert(GtkTreeView, widgetptr)
    event = convert(Gtk.GdkEvent, eventptr)
    list = user_data

    if event.event_type == Gtk.GdkEventType.DOUBLE_BUTTON_PRESS
        open_file(treeview,list)
    end
    return PROPAGATE
end

function filespanel_treeview_keypress_cb(widgetptr::Ptr, eventptr::Ptr, user_data)
    treeview = convert(GtkTreeView, widgetptr)
    event = convert(Gtk.GdkEvent, eventptr)
    list = user_data

    if event.keyval == Gtk.GdkKeySyms.Return
        open_file(treeview,list)
    end

    return PROPAGATE
end

type FilesPanel <: GtkScrolledWindow

    handle::Ptr{Gtk.GObject}
    list::GtkTreeStore
    tree_view::GtkTreeView

    function FilesPanel()

        (tv,list,cols) = files_tree_view(["Icon","Name"])

        signal_connect(filespanel_treeview_clicked_cb,tv, "button-press-event",
        Cint, (Ptr{Gtk.GdkEvent},), false,list)
        signal_connect(filespanel_treeview_keypress_cb,tv, "key-press-event",
        Cint, (Ptr{Gtk.GdkEvent},), false,list)

        sc = @GtkScrolledWindow()
        push!(sc,tv)

        t = new(sc.handle,list,tv)
        Gtk.gobject_move_ref(t,sc)
    end
end

function update!(w::FilesPanel, path::AbstractString, parent=nothing)
    n = readdir(path)
    for el in n
        full_path = joinpath(path,string(el))
        if isdir(full_path)
            pixbuf = GtkIconThemeLoadIconForScale(GtkIconThemeGetDefault(),"folder",24,1,0)
            folder = push!(w.list,(pixbuf,el),parent)
            update!(w,full_path, folder )
        else
           file_parts = splitext(el)
           if  (file_parts[2]==".jl")
             pixbuf = GtkIconThemeLoadIconForScale(GtkIconThemeGetDefault(),"code",24,1,0)
             push!(w.list,(pixbuf,el, joinpath(path,el)),parent)
           end
         end
    end
end

function update!(w::FilesPanel)


    sel_val = selected(w.tree_view,w.list)
    empty!(w.list)
    update!(w,pwd())

    sel_val != nothing && select_value(w.tree_view,w.list,sel_val)
end

filespanel = FilesPanel()
update!(filespanel)
add_side_panel(filespanel,"Files")

#FIXME I should stop all tasks when exiting
#this can make it crash if it runs while sorting
@schedule begin
    while(false)
        sleep(1.0)
        update!(filespanel)
    end
end

#### WORKSPACE PANEL

type WorkspacePanel <: GtkScrolledWindow

    handle::Ptr{Gtk.GObject}
    list::GtkTreeStore
    tree_view::GtkTreeView

    function WorkspacePanel()

        (tv,list,cols) = give_me_a_treeview(2,["Name","Type"])

        sc = @GtkScrolledWindow()
        push!(sc,tv)

        t = new(sc.handle,list,tv)
        Gtk.gobject_move_ref(t,sc)
    end
end

function update!(w::WorkspacePanel)

    ##

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

    ##

    sel_val = selected(w.tree_view,w.list)

    empty!(w.list)
    for i = 1:length(t)
        push!(w.list,(n[i],t[i]))
    end

    sel_val != nothing && select_value(w.tree_view,w.list,sel_val)
end

workspacepanel = WorkspacePanel()
update!(workspacepanel)
add_side_panel(workspacepanel,"W")
