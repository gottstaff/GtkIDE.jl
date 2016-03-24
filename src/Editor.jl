include("EditorUtils.jl")
include("Actions.jl")
include("EditorTab.jl")

"     Editor <: GtkNotebook
"
type Editor <: GtkNotebook

    handle::Ptr{Gtk.GObject}
    sourcemap::Gtk.GtkWidget

    function Editor()

        ntbook = @GtkNotebook()
        setproperty!(ntbook,:scrollable, true)
        setproperty!(ntbook,:enable_popup, false)


        if GtkSourceWidget.SOURCE_MAP #old linux libraries don't have GtkSourceMap
            sourcemap = @GtkSourceMap()
            t = new(ntbook.handle,sourcemap)
        else
            sourcemap = @GtkBox(:v)#put a dummy box instead
            t = new(ntbook.handle,sourcemap)
        end
        Gtk.gobject_move_ref(t, ntbook)
    end
end

if !GtkSourceWidget.SOURCE_MAP
    set_view() = nothing
end

const editor = Editor()

get_current_tab() = get_tab(editor,get_current_page_idx(editor))

function ntbook_switch_page_cb(widgetptr::Ptr, pageptr::Ptr, pagenum::Int32, user_data)

    page = convert(Gtk.GtkWidget, pageptr)
    if typeof(page) == EditorTab && GtkSourceWidget.SOURCE_MAP
        set_view(editor.sourcemap, page.view)
    end
    nothing
end
signal_connect(ntbook_switch_page_cb,editor,"switch-page", Void, (Ptr{Gtk.GtkWidget},Int32), false)

global mousepos = zeros(Int,2)
global mousepos_root = zeros(Int,2)

#I need this to get the mouse position when we use the keyboard
function ntbook_motion_notify_event_cb(widget::Ptr,  eventptr::Ptr, user_data)
    event = convert(Gtk.GdkEvent, eventptr)

    mousepos[1] = round(Int,event.x)
    mousepos[2] = round(Int,event.y)
    mousepos_root[1] = round(Int,event.x_root)
    mousepos_root[2] = round(Int,event.y_root)
    return PROPAGATE
end
signal_connect(ntbook_motion_notify_event_cb,editor,"motion-notify-event",Cint, (Ptr{Gtk.GdkEvent},), false)


function close_tab(idx::Int)
  splice!(editor,idx)
  set_current_page_idx(editor,max(idx-1,0))
end
close_tab() = close_tab(get_current_page_idx(editor))

function close_tab_cb(btn::Ptr, num)
   close_tab(num)
   return nothing
end

function close_other_tabs_cb(btn::Ptr,idx)
  for i =1:Gtk.GAccessor.n_pages(editor)+1
    if (i!=idx)
      splice!(editor,i)
    end
  end
end
function close_tabs_right_cb(btn::Ptr,idx)
  for i =idx+1:Gtk.GAccessor.n_pages(editor)+1
      splice!(editor,i)
  end
end
function close_all_tabs(btn::Ptr,idx)
  for i =1:Gtk.GAccessor.n_pages(editor)+1
      splice!(editor,i)
  end
end
function create_tab_menu(container, idx)
  menu =  @GtkMenu() |>
  (closeTabItem = @GtkMenuItem("Close Tab")) |>
  (closeOthersTabsItem = @GtkMenuItem("Close Others Tabs")) |>
  (closeTabsRight = @GtkMenuItem("Close Tabs to the Right ")) |>
  (closeAllTabs = @GtkMenuItem("Close All Tabs")) |>
  @GtkSeparatorMenuItem() |>
  (revealInTreeItem = @GtkMenuItem("Reveal in Tree View"))

  signal_connect(close_tab_cb, closeTabItem, "activate", Void,(),false,idx)
  signal_connect(close_other_tabs_cb, closeOthersTabsItem, "activate", Void,(),false,idx)
  signal_connect(close_tabs_right_cb, closeTabsRight, "activate", Void,(),false,idx)
  signal_connect(close_all_tabs, closeAllTabs, "activate", Void,(),false,idx)

  showall(menu)
  return menu

end

  function tab_button_press_event_cb(event_box_ptr::Ptr,eventptr::Ptr, idx)
    event_box = convert(GtkEventBox, event_box_ptr)
    event     = convert(Gtk.GdkEvent,eventptr)
    if (event.button == 3)
        popup(create_tab_menu(event_box, idx),event)
        return 1
    else
        return 0
    end
    return 0

end

function get_tab_widget(idx, filename)
    layout = @GtkBox(:h)
    event_box = @GtkEventBox()
    push!(event_box,layout)
    signal_connect(tab_button_press_event_cb, event_box, "button-press-event",Cint, (Ptr{Gtk.GdkEvent},), false,idx)
    lbl = @GtkLabel(basename(filename))
    setproperty!(lbl,:name, "filename_label")
    btn = @GtkButton("X")
    signal_connect(close_tab_cb, btn, "clicked", Void,(),false,idx)


    push!(layout,lbl)
    push!(layout,btn)
    showall(event_box)
    return (event_box, lbl)

end
import Base.open
function open(t::EditorTab, filename::AbstractString)
    try
        if isfile(filename)
            f = Base.open(filename)
            set_text!(t,readall(f))
            t.modified = false
        else
            f = Base.open(filename,"w")
            t.modified = true
        end
        t.filename = filename
        reset_undomanager(t.buffer)#otherwise we can undo loading the file...
        close(f)
    catch err
        @show err
    end
    update!(project)
end

function add_tab(filename::AbstractString)

    t = EditorTab(filename);
    t.scroll_target = 0.
    t.scroll_target_line = 0

    idx = get_current_page_idx(editor)
    (event_box,t.label) = get_tab_widget(idx, filename)
    insert!(editor, idx, t, event_box)
    showall(editor)
    set_current_page_idx(editor,idx)



    Gtk.create_tag(t.buffer, "debug1", font="Normal $fontsize",background="green")
    Gtk.create_tag(t.buffer, "debug2", font="Normal $fontsize",background="blue")
    set_font(t)

    #we need to use the view here to capture all the keystrokes
    signal_connect(tab_key_press_cb,t.view, "key-press-event", Cint, (Ptr{Gtk.GdkEvent},), false,t)
    signal_connect(tab_key_release_cb,t.view, "key-release-event", Cint, (Ptr{Gtk.GdkEvent},), false)
    signal_connect(tab_button_press_cb,t.view, "button-press-event", Cint, (Ptr{Gtk.GdkEvent},), false)

    signal_connect(tab_buffer_changed_cb,t.buffer,"changed", Void, (), false,t)

#    signal_connect(tab_extend_selection_cb,t.view, "extend-selection", Cint,
#    (Ptr{Void},Ptr{Gtk.GtkTextIter},Ptr{Gtk.GtkTextIter},Ptr{Gtk.GtkTextIter}), false)

    signal_connect(tab_adj_changed_cb, getproperty(t.view,:vadjustment,GtkAdjustment) , "changed", Void, (), false,t)

    return t
end
add_tab() = add_tab("Untitled")

function load_tabs(project::Project)

    #project get modified later
    files = project.files
    scroll_position = project.scroll_position
    ntbook_idx = project.ntbook_idx

    for i = 1:length(files)
        t = open_in_new_tab(files[i])
        t.scroll_target = scroll_position[i]
    end

    if length(editor)==0
        open_in_new_tab(joinpath(Pkg.dir(),"GtkIDE","README.md"))
    elseif ntbook_idx <= length(editor)
        set_current_page_idx(editor,ntbook_idx)
    end
    t = get_current_tab()
    GtkSourceWidget.SOURCE_MAP && set_view(editor.sourcemap,t.view)
end

load_tabs(project)
