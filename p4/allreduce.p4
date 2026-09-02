/* P4 skeleton for SmartNIC offload – to be implemented */
header_type_t gradient_hdr_t {
    fields {
        session_id : 32;
        seq_num : 32;
        worker_id : 16;
        payload_floats : 16;
    }
}
parser TopParser { return parse_gradient; }
control Ingress { }