function [head, hdr, img_scaled] = load_ismrmrd_ifft3d_reconstruction(filename)
%LOAD_ISMRMD :  load .h5 file, read header (head) and reconstruct images


if exist(filename, 'file')
    dset = ismrmrd.Dataset(filename, 'dataset');
else
    error(['File ' filename ' does not exist.  Please generate it.'])
end

%% Read some fields from the XML header
% We need to check if optional fields exists before trying to read them
hdr = ismrmrd.xml.deserialize(dset.readxml);

D = dset.readAcquisition();
head=D.head;


%% Encoding and reconstruction information
% Matrix size
rec_Nx = hdr.encoding.reconSpace.matrixSize.x;
rec_Ny = hdr.encoding.reconSpace.matrixSize.y;
rec_Nz = hdr.encoding.reconSpace.matrixSize.z;

% Field of View
enc_FOVx = hdr.encoding.encodedSpace.fieldOfView_mm.x;
enc_FOVy = hdr.encoding.encodedSpace.fieldOfView_mm.y;
enc_FOVz = hdr.encoding.encodedSpace.fieldOfView_mm.z;
rec_FOVx = hdr.encoding.reconSpace.fieldOfView_mm.x;
rec_FOVy = hdr.encoding.reconSpace.fieldOfView_mm.y;
rec_FOVz = hdr.encoding.reconSpace.fieldOfView_mm.z;

% Number of slices, coils, repetitions, contrasts etc.
% We have to wrap the following in a try/catch because a valid xml header may
% not have an entry for some of the parameters
try
    nSlices = hdr.encoding.encodingLimits.slice.maximum + 1;
catch
    nSlices = 1;
end

try
    nCoils = hdr.acquisitionSystemInformation.receiverChannels;
catch
    nCoils = 1;
end

try
    nReps = hdr.encoding.encodingLimits.repetition.maximum + 1;
catch
    nReps = 1;
end

try
    nContrasts = hdr.encoding.encodingLimits.contrast.maximum + 1 + 1;
catch
    nContrasts = 1;
end

try
    set = hdr.encoding.encodingLimits.set.maximum +1;
catch
    set = 1;
end



%% Ignore noise scans
% TODO add a pre-whitening example
% Find the first non-noise scan
% This is how to check if a flag is set in the acquisition header
isNoise = D.head.flagIsSet('ACQ_IS_NOISE_MEASUREMENT');
firstScan = find(isNoise==0,1,'first');
if firstScan > 1
    noise = D.select(1:firstScan-1);
else
    noise = [];
end
meas  = D.select(firstScan:D.getNumber);

%clear D



%% Reconstruct images
% Since the entire file is in memory we can use random access
% Loop over repetitions, contrasts, slices
reconImages = {};
nimages = 0;
for rep = 1:nReps
    for nset = 1:set %store TI1 and TI2 acquisition
        for slice = 1:nSlices
            % Initialize the K-space storage array
            % K = zeros(enc_Nx, enc_Ny, enc_Nz, nCoils);
            % Select the appropriate measurements from the data
            %             acqs = find(  (meas.head.idx.set==(nset-1)) ...
            %                         & (meas.head.idx.repetition==(rep-1)) ...
            %                         & (meas.head.idx.slice==(slice-1)) ...
            %                         & (~ meas.head.flagIsSet('ACQ_IS_NAVIGATION_DATA')) ...
            %                         & (~ meas.head.flagIsSet('ACQ_IS_PHASECORR_DATA')) ...
            %                         & (~ meas.head.flagIsSet('ACQ_IS_PARALLEL_CALIBRATION')) ...
            %                         & (~ meas.head.flagIsSet('ACQ_IS_NOISE_MEASUREMENT')) ...
            %                         & (~ meas.head.flagIsSet('ACQ_IS_DUMMYSCAN_DATA')) ...
            %                         & (~ meas.head.flagIsSet('ACQ_IS_RTFEEDBACK_DATA')) ...
            %                         & (~ meas.head.flagIsSet('ACQ_IS_HPFEEDBACK_DATA')) ...
            %                         & (~ meas.head.flagIsSet('ACQ_IS_SURFACECOILCORRECTIONSCAN_DATA')) ...
            %                         );
            acqs = find(  (meas.head.idx.set==(nset-1)) ...
                & (meas.head.idx.repetition==(rep-1))  ...
                );
            
            for p = 1:length(acqs)
                ky = meas.head.idx.kspace_encode_step_1(acqs(p)) + 1;
                kz = meas.head.idx.kspace_encode_step_2(acqs(p)) + 1;
               % size(meas.data{acqs(p)})
              %  if (size(meas.data{acqs(p)},1) == size(K,1)) % ugly but it works
                    K(:,ky,kz,:) = meas.data{acqs(p)};
             %   end
            end
            clear im_x im_y im im_sos
            % matrix size is wrong maybe because of regridding
            % zf_mat = zeros(round((enc_Nx-size(K,1))/4),size(K,2),size(K,3),size(K,4));
            % K = cat(1,zf_mat,K,zf_mat);
            
            % Reconstruct in x
            im_x = fftshift(ifft(fftshift(K,1),[],1),1);
            % Chop if needed
%             if (enc_Nx == rec_Nx)
%                 im = K;
%             else
%                 ind1 = floor((enc_Nx - rec_Nx)/2)+1;
%                 ind2 = floor((enc_Nx - rec_Nx)/2)+rec_Nx;
%                 im = K(ind1:ind2,:,:,:);
%             end
            % Reconstruct in y then z
            im_y = fftshift(ifft(fftshift(im_x,2),[],2),2);
%             if size(im_y,3)>1
                im = fftshift(ifft(fftshift(im_y,3),[],3),3);
%             end
            
            % Combine SOS across coils
            im_sos = sqrt(sum(abs(im).^2,4));
            
            % Append
            nimages = nimages + 1;
            reconImages{nimages} = im_sos;
        end
    end
end



%% Crop image to have right dimensions
img_scaled = crop_image(reconImages,rec_Nx, rec_Ny, rec_Nz)


end

