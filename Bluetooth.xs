#ifdef __cplusplus
extern "C" {
#endif
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/socket.h>
#include <bluetooth/bluetooth.h>
#include <bluetooth/hci.h>
#include <bluetooth/hci_lib.h>
#include <bluetooth/sdp.h>
#include <bluetooth/sdp_lib.h>
#include <bluetooth/rfcomm.h>
#include <bluetooth/l2cap.h>
#ifdef __cplusplus
}
#endif

typedef PerlIO * InOutStream;

MODULE = Net::Bluetooth	PACKAGE = Net::Bluetooth


void
_close(sock)
	int sock
	PPCODE:
	close(sock);

InOutStream
_perlfh(fd)
	int fd
	CODE:
	InOutStream fh = PerlIO_fdopen(fd, "r+");
	RETVAL = fh;

	OUTPUT:
	RETVAL 


void
get_remote_devices(...)
	PPCODE:
	EXTEND(sp, 1);
	char addr[19];
	char name[248];
	char *local_addr;
    	int len = 8; // 1.28 * len
    	int max_rsp = 255; // max devices
	int flags = IREQ_CACHE_FLUSH; // flush cache of previously discovered devices
	int dev_id;
	bdaddr_t baddr;
	STRLEN n_a;

	if(items > 0) {
		local_addr = (char *) SvPV(ST(1), n_a);
		// str2ba always returns 0
		str2ba(local_addr, &baddr);
		dev_id = hci_get_route(&baddr);
	}

	else {
		dev_id = hci_get_route(NULL);
	}

	if(dev_id < 0) {
		//croak("Invalid device ID returned\n");
		return;
	}

	int sock = hci_open_dev(dev_id);
    	if(sock < 0) {
		//croak("Could not open device socket\n");
        	return;
    	}

    	inquiry_info *ii = (inquiry_info*) malloc(max_rsp * sizeof(inquiry_info));
	if(ii == NULL) {
		croak("malloc failed in get_remote_devices");
		return;
	}

    	int num_rsp = hci_inquiry(dev_id, len, max_rsp, NULL, &ii, flags);
	// hci_inquiry error or no devices found
    	if(num_rsp <= 0) {
		free(ii);
		close(sock);
		return;
	}

	HV *return_hash = newHV();
	int i;
    	for(i = 0; i < num_rsp; i++) {
        	ba2str(&(ii+i)->bdaddr, addr);
        	if(hci_read_remote_name(sock, &(ii+i)->bdaddr, sizeof(name), name, 0) < 0) 
        		strcpy(name, "[unknown]");

		hv_store(return_hash, addr, strlen(addr), newSVpv(name, 0), 0);
    	}

	free(ii);
	PUSHs(sv_2mortal(newRV_inc((SV*) return_hash)));
	close(sock);

void
sdp_search(addr, service, name)
	char *addr
	int service
	char *name
	PPCODE:
	EXTEND(sp, 1);
	uuid_t svc_uuid;
	bdaddr_t target;
	sdp_list_t *response_list = NULL;
	sdp_session_t *session = 0;
	unsigned int portnum = 0;
	char local_host [] = "FF:FF:FF:00:00:00";
                                                                                
	if(strcasecmp(addr, "local") ==  0) 
		str2ba(local_host, &target);

	else
		str2ba(addr, &target);
                                                                                
	// connect to remote or local SDP server
	session = sdp_connect(BDADDR_ANY, &target, SDP_RETRY_IF_BUSY);
	if(session == NULL) 
		return;
                                                                                
	// specify the UUID of the application we are searching for
	// convert the UUID string into a uuid_t
	// if service is 0 search for PUBLIC_BROWSE_GROUP
	if(service == 0) {
		sdp_uuid16_create(&svc_uuid, PUBLIC_BROWSE_GROUP);
	}

	else {
        	//uint16_t service_id = service;
        	sdp_uuid16_create(&svc_uuid, (uint16_t) service);
	}

    	sdp_list_t *search_list = sdp_list_append(NULL, &svc_uuid);
	uint32_t range = 0x0000FFFF;
	sdp_list_t *attrid_list = sdp_list_append(NULL, &range);


	// get a list of service records
	if(sdp_service_search_attr_req(session, search_list, SDP_ATTR_REQ_RANGE, attrid_list, &response_list) != 0) {
    		sdp_list_free(search_list, 0);
    		sdp_list_free(attrid_list, 0);
		return;
        }

        sdp_list_t *r = response_list;

	// go through each of the service records
	// create a hash for each record that matches
	for(; r; r = r->next) {
		sdp_record_t *rec = (sdp_record_t*) r->data;
		sdp_list_t *proto_list;
		HV *return_hash = NULL;

		// get service name
		char buf[256];
		if(sdp_get_service_name(rec, buf, sizeof(buf)) == 0) {
			// no name match requested
			if(!*name) {
				return_hash = newHV();
                        	hv_store(return_hash, "SERVICE_NAME", strlen("SERVICE_NAME"), newSVpv(buf, 0), 0);
			}

			// name matches
			else if(strcasecmp(name, buf) == 0 )  {
				return_hash = newHV();
                        	hv_store(return_hash, "SERVICE_NAME", strlen("SERVICE_NAME"), newSVpv(buf, 0), 0);
			}

			// name doesn't match, skip record
			else {
				sdp_record_free(rec);
				continue;
			}
		}

		else {
			// name doesn't match
			if(*name) {
				sdp_record_free(rec);
				continue;
			}

			else {
				// do not create the key?
			}
		}

		// get service description
		if(sdp_get_service_desc(rec, buf, sizeof(buf)) == 0) {
			if(return_hash == NULL)
				return_hash = newHV();
                        hv_store(return_hash, "SERVICE_DESC", strlen("SERVICE_DESC"), newSVpv(buf, 0), 0);
		} 

		else {
			// do not create the key?
		}
                                                                                                                      
		// get service provider name
		if(! sdp_get_provider_name(rec, buf, sizeof(buf)) == 0) {
			if(return_hash == NULL)
				return_hash = newHV();
                        hv_store(return_hash, "SERVICE_PROV", strlen("SERVICE_PROV"), newSVpv(buf, 0), 0);
		} 

		else {
			// do not create the key?
		}

                                                                                                                   
		// get a list of the protocol sequences
        	if(sdp_get_access_protos(rec, &proto_list) == 0) {
			sdp_list_t *p = proto_list;
			int port;

			if(return_hash == NULL)
				return_hash = newHV();

			if((port = sdp_get_proto_port(p, RFCOMM_UUID)) != 0) {
                        	hv_store(return_hash, "RFCOMM", strlen("RFCOMM"), newSVuv(port), 0);
			} 

			else if((port = sdp_get_proto_port(p, L2CAP_UUID)) != 0) {
                       		hv_store(return_hash, "L2CAP", strlen("L2CAP"), newSVuv(port), 0);
			} 

			else {
                        	hv_store(return_hash, "UNKNOWN", strlen("UNKNOWN"), newSVuv(port), 0);
			}

			// sdp_get_access_protos allocates data on the heap for the
			// protocol list, so we need to free the results...
			for(; p; p = p->next) {
				sdp_list_free((sdp_list_t*)p->data, 0);
			}

			sdp_list_free(proto_list, 0);
		}

		else {

		}

		sdp_record_free(rec);
		if(return_hash != NULL)
			PUSHs(sv_2mortal(newRV_inc((SV*) return_hash)));
	}

	sdp_list_free(response_list, 0);
    	sdp_list_free(search_list, 0);
    	sdp_list_free(attrid_list, 0);
	sdp_close(session);


int
_socket(proto)
	char *proto
	CODE:

	if(strcasecmp(proto, "RFCOMM") == 0)  
		RETVAL = socket(AF_BLUETOOTH, SOCK_STREAM, BTPROTO_RFCOMM);

	else if(strcasecmp(proto, "L2CAP") == 0) 
		RETVAL = socket(AF_BLUETOOTH, SOCK_SEQPACKET, BTPROTO_L2CAP);

	else 
		RETVAL = -1;

	OUTPUT:
	RETVAL 


int
_connect(fd, addr, port, proto)
	int fd
	char *addr
	int port
	char *proto
	CODE:

	if(strcasecmp(proto, "RFCOMM") == 0) {
		struct sockaddr_rc rcaddr;
		rcaddr.rc_family = AF_BLUETOOTH;
		rcaddr.rc_channel = (uint8_t) port;
		str2ba(addr, &rcaddr.rc_bdaddr);

		// connect to server
		if(connect(fd, (struct sockaddr *)&rcaddr, sizeof(rcaddr)) == 0) 
			RETVAL = 0;

		else 
			RETVAL = -1;
	}

	else if(strcasecmp(proto, "L2CAP") == 0) {
		struct sockaddr_l2 l2addr;
		l2addr.l2_family = AF_BLUETOOTH;
    		l2addr.l2_psm = htobs(port);
		str2ba(addr, &l2addr.l2_bdaddr);

		// connect to server
		if(connect(fd, (struct sockaddr *)&l2addr, sizeof(l2addr)) == 0) 
			RETVAL = 0;

		else 
			RETVAL = -1;
	}

	else 
		RETVAL = -1;

	OUTPUT:
	RETVAL 


int
_bind(fd, port, proto)
	int fd
	int port
	char *proto
	CODE:

	if(strcasecmp(proto, "RFCOMM") == 0)  {
		struct sockaddr_rc rcaddr;
		// set the connection parameters 
		rcaddr.rc_family = AF_BLUETOOTH;
		rcaddr.rc_channel = (uint8_t) port;
		rcaddr.rc_bdaddr = *BDADDR_ANY;

		RETVAL = bind(fd, (struct sockaddr *)&rcaddr, sizeof(rcaddr));
	}

	else if(strcasecmp(proto, "L2CAP") == 0) {
		struct sockaddr_l2 l2addr;
		// set the connection parameters 
		l2addr.l2_family = AF_BLUETOOTH;
		l2addr.l2_psm = htobs(port);
		l2addr.l2_bdaddr = *BDADDR_ANY;

		RETVAL = bind(fd, (struct sockaddr *)&l2addr, sizeof(l2addr));
	}

	else 
		RETVAL = -1;

	OUTPUT:
	RETVAL 


int
_listen(fd, backlog)
	int fd
	int backlog
	CODE:
	RETVAL = listen(fd, backlog);

	OUTPUT:
	RETVAL 


void
_accept(fd, proto)
	int fd
	char *proto
	PPCODE:
	EXTEND(sp, 2);
	socklen_t addr_len;
	int res;

	if(strcasecmp(proto, "RFCOMM") == 0) {
		struct sockaddr_rc rcaddr;
		addr_len = sizeof(rcaddr);
		res = accept(fd, (struct sockaddr *)&rcaddr, &addr_len);
		PUSHs(sv_2mortal(newSViv(res)));
		if(res >= 0) {
			char addr[19];
        		ba2str(&rcaddr.rc_bdaddr, addr);
			PUSHs(sv_2mortal(newSVpv(addr, 0)));
		}
	}

	else if(strcasecmp(proto, "L2CAP") == 0) {
		struct sockaddr_l2 l2addr;
		addr_len = sizeof(l2addr);
		res = accept(fd, (struct sockaddr *)&l2addr, &addr_len);
		PUSHs(sv_2mortal(newSViv(res)));
		if(res >= 0) {
			char addr[19];
        		ba2str(&l2addr.l2_bdaddr, addr);
			PUSHs(sv_2mortal(newSVpv(addr, 0)));
		}
	}

	else 
		PUSHs(sv_2mortal(newSViv(-1)));



unsigned int
register_service(proto, port, service_id, name)
	char *proto
	int port
	int service_id
	char *name
	CODE:
	uint8_t rfcomm_channel = 0;
	uint16_t l2cap_port = 0;
	const char *service_name = name;
	const char *service_dsc = name;
	const char *service_prov = name;
                                                                                                                   
	uuid_t root_uuid, l2cap_uuid, rfcomm_uuid, svc_uuid;
	sdp_list_t *l2cap_list = 0,
                   *rfcomm_list = 0,
                   *root_list = 0,
                   *proto_list = 0,
                   *access_proto_list = 0;
	sdp_data_t *channel = 0, *psm = 0;
                                                                                                                   
	sdp_record_t *record = sdp_record_alloc();
                                                                                                                   
	// set the general service ID
	sdp_uuid16_create(&svc_uuid, service_id);
	sdp_set_service_id(record, svc_uuid);
                                                                                                                   
	// make the service record publicly browsable
	sdp_uuid16_create(&root_uuid, PUBLIC_BROWSE_GROUP);
	root_list = sdp_list_append(0, &root_uuid);
	sdp_set_browse_groups(record, root_list);
                                                                                                                   
	// set l2cap information
	sdp_uuid16_create(&l2cap_uuid, L2CAP_UUID);
	l2cap_list = sdp_list_append(0, &l2cap_uuid);
	if(strcasecmp(proto, "L2CAP") == 0) {
    		uint16_t l2cap_port = port;
    		psm = sdp_data_alloc(SDP_UINT16, &l2cap_port);
    		sdp_list_append(l2cap_list, psm);
	}
	proto_list = sdp_list_append(0, l2cap_list);
                                                                                                                   
	// set rfcomm information
	sdp_uuid16_create(&rfcomm_uuid, RFCOMM_UUID);
	rfcomm_list = sdp_list_append(0, &rfcomm_uuid);
	if(strcasecmp(proto, "RFCOMM") == 0) {
    		uint8_t rfcomm_channel = port;
    		channel = sdp_data_alloc(SDP_UINT8, &rfcomm_channel);
    		sdp_list_append(rfcomm_list, channel);
	}
	sdp_list_append(proto_list, rfcomm_list);
                                                                                                                   
	// attach protocol information to service record
	access_proto_list = sdp_list_append( 0, proto_list );
	sdp_set_access_protos( record, access_proto_list );
                                                                                                                   
	// set the name, provider, and description
	sdp_set_info_attr(record, service_name, service_prov, service_dsc);
                                                                                                                   
	// connect to the local SDP server, register the service record, and disconnect
	sdp_session_t *session = sdp_connect(BDADDR_ANY, BDADDR_LOCAL, SDP_RETRY_IF_BUSY);
	if(session) {
		if(sdp_record_register(session, record, 0) >= 0) {
			RETVAL = (unsigned int) session;
		}

		else {
			RETVAL = 0;
		}
	}

	else {
		RETVAL = 0;
	}
                                                                                                                   
	sdp_data_free(channel);
	sdp_list_free(l2cap_list, 0);
	sdp_list_free(rfcomm_list, 0);
	sdp_list_free(root_list, 0);
	sdp_list_free(access_proto_list, 0);
                                                                                                                   
	OUTPUT:
	RETVAL 




void
unregister_service(sdp_addr)
	unsigned int sdp_addr
	CODE:
	sdp_session_t *sdp_session;
	sdp_session = (sdp_session_t *) sdp_addr;
	sdp_close(sdp_session);


void
_getpeername(fd, proto)
	int fd
	char *proto
	PPCODE:
	EXTEND(sp, 2);
	if(strcasecmp(proto, "RFCOMM") == 0) {
		struct sockaddr_rc rcaddr;
		socklen_t len = sizeof(rcaddr);
		if(getpeername(fd, (struct sockaddr *) &rcaddr, &len) == 0) {
			char addr[19];
			ba2str(&rcaddr.rc_bdaddr, addr);
			PUSHs(sv_2mortal(newSVpv(addr, 0)));
			PUSHs(sv_2mortal(newSVuv(rcaddr.rc_channel)));
		}
	}

	else if(strcasecmp(proto, "L2CAP") == 0) {
		struct sockaddr_l2 l2addr;
		socklen_t len = sizeof(l2addr);
		if(getpeername(fd, (struct sockaddr *) &l2addr, &len) == 0) {
			char addr[19];
			ba2str(&l2addr.l2_bdaddr, addr);
			PUSHs(sv_2mortal(newSVpv(addr, 0)));
			PUSHs(sv_2mortal(newSVuv(l2addr.l2_psm)));
		}
	}
