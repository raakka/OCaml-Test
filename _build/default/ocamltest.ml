open H2
module Client = H2_lwt_unix.Client

let response_handler notify_response_received response response_body =
  match response.Response.status with
  | `OK ->
    let rec read_response () =
      Body.schedule_read
        response_body
        ~on_read:(fun bigstring ~off ~len ->
          let response_fragment = Bytes.create len in
          Bigstringaf.blit_to_bytes
            bigstring
            ~src_off:off
            response_fragment
            ~dst_off:0
            ~len;
          print_string (Bytes.to_string response_fragment);
          read_response ())
        ~on_eof:(fun () ->
          Lwt.wakeup_later notify_response_received ())
    in
    read_response ()
  | _ ->
    Format.eprintf "Unsuccessful response: %a\n%!" Response.pp_hum response;
    exit 1

let error_handler _error =
  Format.eprintf "Unsuccessful request!\n%!";
  exit 1

open Lwt.Infix

let () =
  let host = "www.example.com" in
  Lwt_main.run
    (
      Lwt_unix.getaddrinfo host "443" [ Unix.(AI_FAMILY PF_INET) ]
    >>= fun addresses ->
      let socket = Lwt_unix.socket Unix.PF_INET Unix.SOCK_STREAM 0 in
      Lwt_unix.connect socket (List.hd addresses).Unix.ai_addr >>= fun () ->
      let request =
        Request.create
          `GET
          "/"
          ~scheme:"https"
          ~headers:
            Headers.(add_list empty [ ":authority", host ])
      in
      let response_received, notify_response_received = Lwt.wait () in
      let response_handler = response_handler notify_response_received in
      Client.TLS.create_connection_with_default ~error_handler socket >>= fun connection ->
      let request_body =
        Client.TLS.request connection request ~error_handler ~response_handler
      in
      Body.close_writer request_body;
      response_received )
