
type FilesPanel <: GtkScrolledWindow
  handle::Ptr{Gtk.GObject}
  list::GtkTreeStore
  tree_view::GtkTreeView
  menu::GtkMenu
  current_path::AbstractString
  function FilesPanel()
    sc = @GtkScrolledWindow()
    (tv,list,cols) = files_tree_view(["Icon","Name"])
    push!(sc,tv)

    t = new(sc.handle,list,tv);

    t.menu = filespanel_context_menu_create(t)

    signal_connect(filespanel_treeview_clicked_cb,tv, "button-press-event",
    Cint, (Ptr{Gtk.GdkEvent},), false,t)
    signal_connect(filespanel_treeview_keypress_cb,tv, "key-press-event",
    Cint, (Ptr{Gtk.GdkEvent},), false,t)
    Gtk.gobject_move_ref(t,sc)
  end
end
function filespanel_context_menu_create(t::FilesPanel)
  menu = @GtkMenu(file) |>
  (changeDirectoryItem = @GtkMenuItem("Change Directory")) |>
  (addToPathItem = @GtkMenuItem("Add to Pah")) |>
  @GtkSeparatorMenuItem() |>
  (newFileItem = @GtkMenuItem("New File")) |>
  (newFolderItem = @GtkMenuItem("New Folder")) |>
  @GtkSeparatorMenuItem() |>
  (deleteItem = @GtkMenuItem("Delete")) |>
  (renameItem = @GtkMenuItem("Rename")) |>
  (copyItem = @GtkMenuItem("Copy")) |>
  (cutItem = @GtkMenuItem("Cut")) |>
  (pasteItem = @GtkMenuItem("Paste")) |>
  @GtkSeparatorMenuItem() |>
  (copyFullPathItem = @GtkMenuItem("Copy Full Path"))

  signal_connect(filespanel_newFileItem_activate_cb, newFileItem,
  "activate",Void, (),false,t)
  signal_connect(filespanel_deleteItem_activate_cb, deleteItem,
  "activate",Void, (),false,t)
  signal_connect(filespanel_renameItem_activate_cb, renameItem,
  "activate",Void, (),false,t)
  return menu
end


function update!(w::FilesPanel, path::AbstractString, parent=nothing)
  pixbuf = GtkIconThemeLoadIconForScale(GtkIconThemeGetDefault(),"folder",24,1,0)
  folder = push!(w.list,(pixbuf,basename(path),path),parent)
  n = readdir(path)
  for el in n
    full_path = joinpath(path,string(el))
    if isdir(full_path)
      update!(w,full_path, folder )
    else
      file_parts = splitext(el)
      if  (file_parts[2]==".jl")
        pixbuf = GtkIconThemeLoadIconForScale(GtkIconThemeGetDefault(),"code",24,1,0)
        push!(w.list,(pixbuf,el, joinpath(path,el)),folder)
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
#### FILES PANEL
function get_selected_path(treeview::GtkTreeView,list::GtkTreeStore)
  v = selected(treeview, list)
  if v != nothing && length(v) == 3
    return v[3]
  else
    return nothing
  end
end
function get_selected_file(treeview::GtkTreeView,list::GtkTreeStore)
  path = get_selected_path(treeview,list)
  if (isfile(path))
    return path
  else
    return nothing
  end
end
function open_file(treeview::GtkTreeView,list::GtkTreeStore)
  file = get_selected_file(treeview,list)
  if file != nothing
    open_in_new_tab(file)
  end
end
#=File path menu =#
function path_dialog_create_file_cb(ptr::Ptr, filename)
  touch(getproperty(filename, :text, AbstractString))
  update!(filespanel)
  return nothing
end
function path_dialog_rename_file_cb(ptr::Ptr, previous_filename, filename)
  mv(previous_filename,filename)
  update!(filespanel)
  return nothing
end
function path_dialog_filename_inserted_text(text_entry_buffer_ptr::Ptr, cursor_pos,new_text::Cstring,n_chars,data)
  path = data[1]
  delete_signal_id = data[2]
  text_entry_buffer = convert(GtkEntryBuffer, text_entry_buffer_ptr)
  if (cursor_pos < length(path))
    Gtk.signal_handler_block(text_entry_buffer, delete_signal_id[])
    delete_text(text_entry_buffer,cursor_pos,n_chars)
    Gtk.signal_handler_unblock(text_entry_buffer, delete_signal_id[])
  end
  return nothing
end
function path_dialog_filename_deleted_text(text_entry_buffer_ptr::Ptr, cursor_pos,n_chars,data)
  path = data[1]
  insert_signal_id = data[2]
  text_entry_buffer = convert(GtkEntryBuffer, text_entry_buffer_ptr)
  if (cursor_pos < length(path))

    Gtk.signal_handler_block(text_entry_buffer, insert_signal_id[])
    insert_text(text_entry_buffer,cursor_pos, path[cursor_pos+1:min(end,cursor_pos+n_chars+1)],n_chars)
    Gtk.signal_handler_unblock(text_entry_buffer, insert_signal_id[])
  end
  return nothing
end

function configure_text_entry_fixed_content(te, fixed, nonfixed="")

  setproperty!(te, :text,string(fixed,nonfixed));
  te = buffer(te)
  const id_signal_insert = [Culong(0)]
  const id_signal_delete = [Culong(0)]
  id_signal_insert[1] = signal_connect(path_dialog_filename_inserted_text,
  te,
  "inserted-text",
  Void,
  (Cuint,Cstring,Cuint),false,(fixed,id_signal_delete))
  id_signal_delete[1] = signal_connect(path_dialog_filename_deleted_text,
  te,
  "deleted-text",
  Void,
  (Cuint,Cuint),false,(fixed,id_signal_insert))
end

function show_file_path_dialog(action::Function,path,filename="")
  path = string(path,"/")
  b = Gtk.GtkBuilderLeaf(filename=joinpath(dirname(@__FILE__),"forms/forms.glade"))
  w = GAccessor.object(b,"DialogCreateFile")
  btn_create_file = GAccessor.object(b,"btnCreateFile")
  te_filename = GAccessor.object(b,"filename")
  configure_text_entry_fixed_content(te_filename,path,filename)
  signal_connect(action,btn_create_file, "clicked",Void,(),false,(te_filename))
  showall(w)
end
#==========#



function filespanel_treeview_clicked_cb(widgetptr::Ptr, eventptr::Ptr, filespanel)
  treeview = convert(GtkTreeView, widgetptr)
  event = convert(Gtk.GdkEvent, eventptr)

  list = filespanel.list
  menu = filespanel.menu
  if event.button == 3
    (ret,current_path) = Gtk.path_at_pos(treeview,round(Int,event.x),round(Int,event.y));
    if ret
      (ret,current_iter) = Gtk.iter(Gtk.GtkTreeModel(filespanel.list),current_path)
      filespanel.current_path = Gtk.getindex(filespanel.list,current_iter,3)
      showall(menu)
      popup(menu,event)
    end
  else
    if event.event_type == Gtk.GdkEventType.DOUBLE_BUTTON_PRESS
      open_file(treeview,list)
    end
  end

  return PROPAGATE
end

function filespanel_treeview_keypress_cb(widgetptr::Ptr, eventptr::Ptr, filespanel)
  treeview = convert(GtkTreeView, widgetptr)
  event = convert(Gtk.GdkEvent, eventptr)
  list = filespanel.list

  if event.keyval == Gtk.GdkKeySyms.Return
    open_file(treeview,list)
  end

  return PROPAGATE
end

function filespanel_newFileItem_activate_cb(widgetptr::Ptr,filespanel)
  if (filespanel.current_path!=nothing)
    if isfile(filespanel.current_path)
      current_path = dirname(filespanel.current_path)
    else
      current_path = filespanel.current_path
    end
    show_file_path_dialog(path_dialog_create_file_cb,current_path)
  end
  return nothing
end

function filespanel_deleteItem_activate_cb(widgetptr::Ptr,filespanel)
  if (filespanel.current_path!=nothing)
    rm(filespanel.current_path,recursive=true)
  end
  return nothing
end
function filespanel_renameItem_activate_cb(widgetptr::Ptr,filespanel)
  if (filespanel.current_path!=nothing)
    base_path = dirname(filespanel.current_path)
    resource  = filespanel.current_path[length(base_path)+2:end]
    rename_callback = (ptr::Ptr, filename) -> path_dialog_rename_file_cb(ptr,filespanel.current_path,filename)

    show_file_path_dialog(rename_callback,base_path,resource)
  end
  return nothing
end
