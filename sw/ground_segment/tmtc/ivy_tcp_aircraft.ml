let my_id = 0
module Tm_Pprz = Pprz.Messages(struct let _type = "donwlink" and single_class = "" end)
module Dl_Pprz = Pprz.Messages(struct let _type = "uplink" and single_class = "" end)
module PprzTransport = Serial.Transport(Pprz.Transport)

open Printf
let () =
  let ivy_bus = ref Defivybus.default_ivy_bus  in
  let host = ref "10.31.1.98"
  and port = ref 4242
  and id = ref "6" in

  let options = [
    "-b", Arg.Set_string ivy_bus, (sprintf "<ivy bus> Default is %s" !ivy_bus);
    "-h", Arg.Set_string host, (sprintf "<remote host> Default is %s" !host);
    "-id", Arg.Set_string id , (sprintf "<id> Default is %s" !host);
    "-p", Arg.Set_int port, (sprintf "<remote port> Default is %d" !port)
  ] in
  Arg.parse
    options
    (fun x -> fprintf stderr "Warning: Discarding '%s'" x)
    "Usage: ";

  Ivy.init "ivy_tcp" "READY" (fun _ _ -> ());
  Ivy.start !ivy_bus;

  let addr = Unix.inet_addr_of_string !host in
  let sockaddr = Unix.ADDR_INET (addr, !port) in

  let (i, o) = Unix.open_connection sockaddr in

  let get_ivy_message = fun _ args ->
    try
      let (msg_id, vs) = Tm_Pprz.values_of_string args.(0) in
      let payload = Tm_Pprz.payload_of_values (int_of_string !id) (Tm_Pprz.class_id_of_msg_args args.(0)) msg_id vs in 
      let buf = Pprz.Transport.packet payload in
      fprintf o "%s%!" buf
    with _ -> () in
  let _b = Ivy.bind get_ivy_message (sprintf "^%s (.*)" !id) in

  (* Forward a datalink command on the bus *)
  let buffer_size = 256 in
  let buffer = String.create buffer_size in
  let get_datalink_message = fun _ ->
    begin
      try
	let n = input i buffer 0 buffer_size in
	let b = String.sub buffer 0 n in
	Debug.trace 'x' (Debug.xprint b);

	let use_dl_message = fun payload ->
	  Debug.trace 'x' (Debug.xprint (Serial.string_of_payload payload));
	  let (packet_seq, ac_id, class_id, msg_id, values) = Dl_Pprz.values_of_payload payload in
	  let msg = Dl_Pprz.message_of_id class_id msg_id in
	  Dl_Pprz.message_send "ground_dl" msg.Pprz.name values in

	assert (PprzTransport.parse use_dl_message b = n)
      with
	exc ->
	  prerr_endline (Printexc.to_string exc)
    end;
    true in

  let ginput = GMain.Io.channel_of_descr (Unix.descr_of_in_channel i) in
  ignore (Glib.Io.add_watch [`IN] get_datalink_message ginput);

  let hangup = fun _ -> prerr_endline "hangup"; exit 1 in
  ignore (Glib.Io.add_watch [`HUP] hangup ginput);

  (* Main Loop *)
  GMain.main ()
