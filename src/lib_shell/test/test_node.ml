(*****************************************************************************)
(*                                                                           *)
(* Open Source License                                                       *)
(* Copyright (c) 2020 Nomadic Labs. <contact@nomadic-labs.com>               *)
(*                                                                           *)
(* Permission is hereby granted, free of charge, to any person obtaining a   *)
(* copy of this software and associated documentation files (the "Software"),*)
(* to deal in the Software without restriction, including without limitation *)
(* the rights to use, copy, modify, merge, publish, distribute, sublicense,  *)
(* and/or sell copies of the Software, and to permit persons to whom the     *)
(* Software is furnished to do so, subject to the following conditions:      *)
(*                                                                           *)
(* The above copyright notice and this permission notice shall be included   *)
(* in all copies or substantial portions of the Software.                    *)
(*                                                                           *)
(* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR*)
(* IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,  *)
(* FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL   *)
(* THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER*)
(* LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING   *)
(* FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER       *)
(* DEALINGS IN THE SOFTWARE.                                                 *)
(*                                                                           *)
(*****************************************************************************)

(** Unit tests for node. Currently only tests that
   events are emitted. *)

let section = Some (Internal_event.Section.make_sanitized ["node"])

let filter = Some section

let init_config (* (f : 'a -> unit -> unit Lwt.t) *) f test_dir switch () :
    unit Lwt.t =
  let sandbox_parameters : Data_encoding.json = `Null in
  let config : Node.config =
    {
      genesis = Shell_test_helpers.genesis;
      chain_name = Distributed_db_version.Name.zero;
      sandboxed_chain_name = Distributed_db_version.Name.zero;
      user_activated_upgrades = [];
      user_activated_protocol_overrides = [];
      data_dir = test_dir;
      store_root = test_dir;
      context_root = test_dir;
      protocol_root = test_dir;
      patch_context = None;
      p2p = None;
      checkpoint = None;
      disable_mempool = false;
      enable_testchain = true;
    }
  in
  f sandbox_parameters config switch ()

let default_p2p : P2p.config =
  {
    listening_port = None;
    listening_addr = Some (P2p_addr.of_string_exn "[::]");
    discovery_port = None;
    discovery_addr = Some Ipaddr.V4.any;
    trusted_points = [];
    peers_file = "";
    private_mode = true;
    identity = P2p_identity.generate_with_target_0 ();
    proof_of_work_target = Crypto_box.default_target;
    trust_discovered_peers = false;
    reconnection_config = P2p_point_state.Info.default_reconnection_config;
  }

let default_p2p_limits : P2p.limits =
  {
    connection_timeout = Time.System.Span.of_seconds_exn 10.;
    authentication_timeout = Time.System.Span.of_seconds_exn 5.;
    greylist_timeout = Time.System.Span.of_seconds_exn 86400. (* one day *);
    maintenance_idle_time =
      Time.System.Span.of_seconds_exn 120. (* two minutes *);
    min_connections = 10;
    expected_connections = 50;
    max_connections = 100;
    backlog = 20;
    max_incoming_connections = 20;
    max_download_speed = None;
    max_upload_speed = None;
    read_buffer_size = 1 lsl 14;
    read_queue_size = None;
    write_queue_size = None;
    incoming_app_message_queue_size = None;
    incoming_message_queue_size = None;
    outgoing_message_queue_size = None;
    max_known_points = Some (400, 300);
    max_known_peer_ids = Some (400, 300);
    swap_linger = Time.System.Span.of_seconds_exn 30.;
    binary_chunks_size = None;
  }

let default_p2p = Some (default_p2p, default_p2p_limits)

let wrap f _switch () =
  Shell_test_helpers.with_empty_mock_sink (fun _ ->
      Lwt_utils_unix.with_tempdir "tezos_test_" (fun test_dir ->
          init_config f test_dir _switch ()))

(** Start tests *)

let ( >>=?? ) m f =
  m
  >>= function
  | Ok v ->
      f v
  | Error error ->
      Format.printf "Error:\n   %a\n" pp_print_error error ;
      Format.print_flush () ;
      Lwt.return_unit

let test_event msg (level1, section1, status1) (level2, section2, json2) =
  Alcotest.(check (option Shell_test_helpers.Mock_sink.testable_section))
    (msg ^ ". Section")
    section1
    section2 ;
  Alcotest.(check Shell_test_helpers.Mock_sink.testable_level)
    (msg ^ ". Level")
    level1
    level2 ;
  match json2 with
  | `O [("shell-node.v0", `String status2)] ->
      Alcotest.(check string)
        (msg ^ ". Should have correct status")
        status1
        status2
  | _ ->
      Alcotest.fail
        (Format.asprintf
           "%s. Incorrect json format :\n%a"
           msg
           Data_encoding.Json.pp
           json2)

let node_sandbox_initialization_events sandbox_parameters config _switch () =
  Node.create
    ~sandboxed:true
    ~sandbox_parameters
    ~singleprocess:true
    (* Tezos_shell.Node.config *)
    config
    (* Tezos_shell.Node.peer_validator_limits *)
    Node.default_peer_validator_limits
    (* Tezos_shell.Node.block_validator_limits *)
    Node.default_block_validator_limits
    (* Tezos_shell.Node.prevalidator_limits *)
    Node.default_prevalidator_limits
    (* Tezos_shell.Node.chain_validator_limits *)
    Node.default_chain_validator_limits
    (* Tezos_shell_services.History_mode.t option *)
    None
  >>=?? fun n ->
  (* Start tests *)
  let open Shell_test_helpers in
  let evs = Mock_sink.get_events ~filter () in
  Alcotest.(check int) "should have one event" 1 (List.length evs) ;
  test_event
    "Should have an p2p_layer_disabled"
    (Internal_event.Notice, section, "p2p_layer_disabled")
    (List.nth evs 0) ;
  (* End tests *)
  Node.shutdown n

let node_initialization_events _sandbox_parameters config _switch () =
  Node.create
    ~sandboxed:false
    ~singleprocess:true
    (* Tezos_shell.Node.config *)
    {config with p2p = default_p2p}
    (* Tezos_shell.Node.peer_validator_limits *)
    Node.default_peer_validator_limits
    (* Tezos_shell.Node.block_validator_limits *)
    Node.default_block_validator_limits
    (* Tezos_shell.Node.prevalidator_limits *)
    Node.default_prevalidator_limits
    (* Tezos_shell.Node.chain_validator_limits *)
    Node.default_chain_validator_limits
    (* Tezos_shell_services.History_mode.t option *)
    None
  >>=?? fun n ->
  (* Start tests *)
  let open Shell_test_helpers in
  let evs = Mock_sink.get_events ~filter () in
  Alcotest.(check int) "should have two events" 2 (List.length evs) ;
  test_event
    "Should have a p2p bootstrapping event"
    (Internal_event.Notice, section, "bootstrapping")
    (List.nth evs 0) ;
  test_event
    "Should have a p2p_maintain_started event"
    (Internal_event.Notice, section, "p2p_maintain_started")
    (List.nth evs 1) ;
  (* End tests *)
  Node.shutdown n

let node_store_known_protocol_events _sandbox_parameters config _switch () =
  Node.create
    ~sandboxed:false
    ~singleprocess:true
    (* Tezos_shell.Node.config *)
    {config with p2p = default_p2p}
    (* Tezos_shell.Node.peer_validator_limits *)
    Node.default_peer_validator_limits
    (* Tezos_shell.Node.block_validator_limits *)
    Node.default_block_validator_limits
    (* Tezos_shell.Node.prevalidator_limits *)
    Node.default_prevalidator_limits
    (* Tezos_shell.Node.chain_validator_limits *)
    Node.default_chain_validator_limits
    (* Tezos_shell_services.History_mode.t option *)
    None
  >>=?? fun n ->
  (* Start tests *)
  let open Shell_test_helpers in
  (* let evs = Mock_sink.get_events ~filter () in *)
  Mock_sink.assert_has_event
    "Should have a store_protocol_incorrect_hash event"
    ~filter
    ( Internal_event.Info,
      section,
      `O
        [ ( "store_protocol_incorrect_hash.v0",
            `String "ProtoDemoNoopsDemoNoopsDemoNoopsDemoNoopsDemo6XBoYp" ) ]
    ) ;
  (* End tests *)
  Node.shutdown n

let tests =
  [ Alcotest_lwt.test_case
      "node_sandbox_initialization_events"
      `Quick
      (wrap node_sandbox_initialization_events);
    Alcotest_lwt.test_case
      "node_initialization_events"
      `Quick
      (wrap node_initialization_events) ]
