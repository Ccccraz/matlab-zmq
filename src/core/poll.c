#include <mex.h>
#include <errno.h>
#include <string.h>
#include <zmq.h>

// % Example usage:
// % ZMQ_POLLIN = 1,  ZMQ_POLLOUT = 2
// items(1).socket = socket1;
// items(1).events = bitor(ZMQ_POLLIN, ZMQ_POLLOUT);
// items(2).socket = socket2;
// items(2).events = ZMQ_POLLIN;

// % Poll with 1000ms timeout
// [results, count] = zmq.core.poll(items, 1000);

// % Check results
// for i = 1:length(results)
//     if bitand(results(i).revents, ZMQ_POLLIN)
//         % Socket is ready for reading
//     end
//     if bitand(results(i).revents, ZMQ_POLLOUT)
//         % Socket is ready for writing
//     end
// end

// Helper function prototypes
static void validate_input(int nlhs, int nrhs, const mxArray *prhs[]);
static void parse_poll_items(const mxArray *items_array, zmq_pollitem_t *poll_items, int nitems);
static void create_output(mxArray *plhs[], const zmq_pollitem_t *poll_items, int nitems, int result);

void mexFunction(int nlhs, mxArray *plhs[], int nrhs, const mxArray *prhs[])
{
    zmq_pollitem_t *poll_items;
    int nitems, timeout, result;
    
    // Validate inputs
    validate_input(nlhs, nrhs, prhs);
    
    // Get number of items to poll
    nitems = (int)mxGetM(prhs[0]);
    
    // Allocate poll items array
    poll_items = (zmq_pollitem_t *)mxCalloc(nitems, sizeof(zmq_pollitem_t));
    
    // Parse input structure array into poll items
    parse_poll_items(prhs[0], poll_items, nitems);
    
    // Get timeout value
    timeout = (int)mxGetScalar(prhs[1]);
    
    // Call zmq_poll
    result = zmq_poll(poll_items, nitems, timeout);
    
    // Handle errors
    if (result == -1) {
        mxFree(poll_items);
        switch (errno) {
            case ETERM:
                mexErrMsgIdAndTxt("zmq:core:poll:contextTerminated",
                    "Error: At least one socket's context was terminated");
                break;
            case EFAULT:
                mexErrMsgIdAndTxt("zmq:core:poll:invalidItems",
                    "Error: Poll items array is not valid");
                break;
            case EINTR:
                mexErrMsgIdAndTxt("zmq:core:poll:interrupted",
                    "Error: Poll operation was interrupted");
                break;
            default:
                mexErrMsgIdAndTxt("zmq:core:poll:unknown",
                    "Error: Unknown polling error occurred");
        }
    }
    
    // Create output structure array with results
    create_output(plhs, poll_items, nitems, result);
    
    // Clean up
    mxFree(poll_items);
}

static void validate_input(int nlhs, int nrhs, const mxArray *prhs[])
{
    // Check number of inputs and outputs
    if (nrhs != 2) {
        mexErrMsgIdAndTxt("zmq:core:poll:invalidArgs",
            "Two inputs required: poll_items structure array and timeout");
    }
    if (nlhs > 2) {
        mexErrMsgIdAndTxt("zmq:core:poll:invalidOutputs",
            "Maximum of two outputs supported");
    }
    
    // Validate first argument is structure array
    if (!mxIsStruct(prhs[0])) {
        mexErrMsgIdAndTxt("zmq:core:poll:invalidItems",
            "First argument must be a structure array");
    }
    
    // Validate timeout is scalar
    if (!mxIsScalar(prhs[1]) || !mxIsNumeric(prhs[1])) {
        mexErrMsgIdAndTxt("zmq:core:poll:invalidTimeout",
            "Timeout must be a numeric scalar");
    }
}

static void parse_poll_items(const mxArray *items_array, zmq_pollitem_t *poll_items, int nitems)
{
    mxArray *socket_field, *events_field;
    const char *field_names[] = {"socket", "events"};
    
    // Get field positions
    int socket_field_num = mxGetFieldNumber(items_array, "socket");
    int events_field_num = mxGetFieldNumber(items_array, "events");
    
    if (socket_field_num == -1 || events_field_num == -1) {
        mexErrMsgIdAndTxt("zmq:core:poll:missingFields",
            "Poll items must have 'socket' and 'events' fields");
    }
    
    // Parse each poll item
    for (int i = 0; i < nitems; i++) {
        socket_field = mxGetFieldByNumber(items_array, i, socket_field_num);
        events_field = mxGetFieldByNumber(items_array, i, events_field_num);
        
        if (!socket_field || !events_field) {
            mexErrMsgIdAndTxt("zmq:core:poll:invalidField",
                "Invalid field in poll item %d", i+1);
        }
        
        // Get socket pointer
        void **socket_ptr = (void **)mxGetData(socket_field);
        poll_items[i].socket = *socket_ptr;
        poll_items[i].fd = 0;  // Not supporting file descriptors for now
        
        // Get events flags
        poll_items[i].events = (short)mxGetScalar(events_field);
    }
}

static void create_output(mxArray *plhs[], const zmq_pollitem_t *poll_items, int nitems, int result)
{
    const char *field_names[] = {"socket", "revents"};
    mxArray *socket_field, *revents_field;
    
    // Create output structure array
    plhs[0] = mxCreateStructMatrix(nitems, 1, 2, field_names);
    
    // Fill output structure
    for (int i = 0; i < nitems; i++) {
        // Create socket pointer field
        socket_field = mxCreateNumericMatrix(1, 1, sizeof(void*)==8 ? mxUINT64_CLASS : mxUINT32_CLASS, mxREAL);
        void **socket_ptr = (void **)mxGetData(socket_field);
        *socket_ptr = poll_items[i].socket;
        
        // Create revents field
        revents_field = mxCreateDoubleScalar((double)poll_items[i].revents);
        
        // Set fields in structure
        mxSetField(plhs[0], i, "socket", socket_field);
        mxSetField(plhs[0], i, "revents", revents_field);
    }
    
    // Set second output argument (number of events) if requested
    if (plhs[1]) {
        plhs[1] = mxCreateDoubleScalar((double)result);
    }
}